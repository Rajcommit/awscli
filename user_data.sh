#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s) 2>&1

echo "[user-data] Starting bootstrap at $(date --iso-8601=seconds)"

if ! command -v dnf >/dev/null 2>&1; then
  echo "[user-data] dnf not found; this script expects Amazon Linux 2023" >&2
  exit 1
fi

dnf -y update

dnf -y swap curl-minimal curl || dnf -y install curl --allowerasing

dnf -y install \
  httpd \
  php \
  php-cli \
  php-pdo \
  php-mysqlnd \
  php-json \
  php-gd \
  php-common \
  php-mbstring \
  firewalld \
  unzip \
  mariadb105

systemctl enable --now httpd firewalld

firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload || true

APP_ROOT="/var/www/html/comics"
UPLOAD_DIR="${APP_ROOT}/uploads/sample"
RDS_HOST="rohurds.c49gci4ay5yo.us-east-1.rds.amazonaws.com"
RDS_USER="rohurds"
RDS_PASS="redhatrohini"
RDS_DB="databse"

mkdir -p "${APP_ROOT}/assets/css" "${APP_ROOT}/lib/views" "$UPLOAD_DIR"

cat <<'PHP' >/var/www/html/index.php
<?php
header("Location: /comics/", true, 302);
exit;
PHP

cat <<'PHP' >"${APP_ROOT}/lib/app.php"
<?php
require __DIR__ . '/models.php';

class App {
  public function run() {
    $uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
    if ($uri === '/' || $uri === '/comics' || $uri === '/comics/') {
      (new ComicController())->list();
    } elseif (preg_match('#^/comics/([^/]+)$#', $uri, $m)) {
      (new ComicController())->view($m[1]);
    } elseif (preg_match('#^/comics/([^/]+)/([0-9]+)$#', $uri, $m)) {
      (new ComicController())->chapter($m[1], (int) $m[2]);
    } elseif ($uri === '/ping') {
      echo 'pong';
    } else {
      header('Location: /comics');
      exit;
    }
  }
}

class ComicController {
  public function list() {
    $model = new ComicModel();
    $comics = $model->getAll();
    include __DIR__ . '/views/list.php';
  }

  public function view($slug) {
    $model = new ComicModel();
    $comic = $model->getBySlug($slug);
    if (!$comic) {
      http_response_code(404);
      echo 'Comic not found';
      return;
    }
    $chapters = $model->getChapters($comic['id']);
    include __DIR__ . '/views/view.php';
  }

  public function chapter($slug, $chapterNumber) {
    $model = new ComicModel();
    $comic = $model->getBySlug($slug);
    if (!$comic) {
      http_response_code(404);
      echo 'Comic not found';
      return;
    }
    $chapters = $model->getChapters($comic['id']);
    $chapter = null;
    foreach ($chapters as $candidate) {
      if ((int) $candidate['chapter_number'] === $chapterNumber) {
        $chapter = $candidate;
        break;
      }
    }
    if (!$chapter) {
      http_response_code(404);
      echo 'Chapter not found';
      return;
    }
    $pages = $model->getPages($chapter['id']);
    include __DIR__ . '/views/chapter.php';
  }
}
PHP

cat <<'PHP' >"${APP_ROOT}/lib/models.php"
<?php
class ComicModel {
  protected $pdo;

  public function __construct() {
    $dsn = 'mysql:host=rohurds.c49gci4ay5yo.us-east-1.rds.amazonaws.com;dbname=databse;charset=utf8mb4';
    $username = 'rohurds';
    $password = 'redhatrohini';
    $this->pdo = new PDO($dsn, $username, $password, [
      PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
      PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
  }

  public function getAll(): array {
    $stmt = $this->pdo->query('SELECT * FROM comics ORDER BY id DESC');
    return $stmt ? $stmt->fetchAll() : [];
  }

  public function getBySlug(string $slug): ?array {
    $stmt = $this->pdo->prepare('SELECT * FROM comics WHERE slug = ? LIMIT 1');
    $stmt->execute([$slug]);
    $row = $stmt->fetch();
    return $row ?: null;
  }

  public function getChapters(int $comicId): array {
    $stmt = $this->pdo->prepare('SELECT * FROM chapters WHERE comic_id = ? ORDER BY chapter_number ASC');
    $stmt->execute([$comicId]);
    return $stmt->fetchAll();
  }

  public function getPages(int $chapterId): array {
    $stmt = $this->pdo->prepare('SELECT * FROM pages WHERE chapter_id = ? ORDER BY page_number ASC');
    $stmt->execute([$chapterId]);
    return $stmt->fetchAll();
  }
}
PHP

cat <<'PHP' >"${APP_ROOT}/lib/views/list.php"
<?php $totalComics = count($comics); ?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Comics Hub</title>
  <link rel="stylesheet" href="/comics/assets/css/site.css">
</head>
<body>
  <nav class="navbar">
    <div class="navbar__brand">COMICS HUB</div>
    <div class="navbar__links">
      <a href="/comics">Home</a>
      <a href="/ping">Health Check</a>
      <a href="https://aws.amazon.com/" target="_blank" rel="noopener">Built on AWS</a>
    </div>
  </nav>

  <header class="hero">
    <div class="hero__content">
      <span class="hero__badge">Curated library &bull; <?= $totalComics ?> titles</span>
      <h1 class="hero__title">Escape into stunning comic universes.</h1>
      <p class="hero__subtitle">Discover indie adventures, epic sagas, and beautifully illustrated stories served straight from your AWS stack.</p>
      <div class="hero__actions">
        <a class="btn btn--primary" href="/comics">Browse catalog</a>
        <a class="btn btn--ghost" href="/ping">Check service status</a>
      </div>
    </div>
    <div class="hero__cloud"></div>
  </header>

  <main>
    <section class="container">
      <h2 class="section-title">Featured comics</h2>
      <div class="comic-grid">
        <?php foreach ($comics as $comic): ?>
          <?php
            $slug = htmlspecialchars($comic['slug'], ENT_QUOTES, 'UTF-8');
            $title = htmlspecialchars($comic['title'], ENT_QUOTES, 'UTF-8');
            $desc = htmlspecialchars($comic['description'] ?? 'A brand-new adventure awaits.', ENT_QUOTES, 'UTF-8');
            $thumbUrl = 'https://source.unsplash.com/700x420/?' . rawurlencode($comic['slug']) . ',comic,art';
          ?>
          <article class="comic-card">
            <div class="comic-card__thumb" style="background-image:url('<?= $thumbUrl ?>');"></div>
            <div class="comic-card__body">
              <div class="status-pill">New issue online</div>
              <h3 class="comic-card__title"><?= $title ?></h3>
              <p class="comic-card__description"><?= $desc ?></p>
              <div class="meta-row">
                <span>&#9733; Fan favorite</span>
                <span>&bull;</span>
                <span>Updated weekly</span>
              </div>
              <div class="hero__actions" style="margin-top:1rem;">
                <a class="btn btn--primary" style="padding:0.6rem 1.1rem; font-size:0.85rem;" href="/comics/<?= $slug ?>">Jump in</a>
              </div>
            </div>
          </article>
        <?php endforeach; ?>
      </div>
    </section>

    <section class="container panel">
      <h2 class="section-title">Two layers of reliability</h2>
      <p>Infrastructure hardened with Amazon EC2, Auto Scaling, RDS, and a load-balanced edge. Each story you surface here is powered by automation and resilience.</p>
    </section>
  </main>

  <footer>
    &copy; <?= date('Y') ?> Comics Hub &middot; Crafted with love on AWS
  </footer>
</body>
</html>
PHP

cat <<'PHP' >"${APP_ROOT}/lib/views/view.php"
<?php
  $title = htmlspecialchars($comic['title'], ENT_QUOTES, 'UTF-8');
  $slug = htmlspecialchars($comic['slug'], ENT_QUOTES, 'UTF-8');
  $description = htmlspecialchars($comic['description'] ?? 'An epic tale unfolds.', ENT_QUOTES, 'UTF-8');
  $chapterTotal = count($chapters);
  $thumbUrl = 'https://source.unsplash.com/1200x600/?' . rawurlencode($comic['slug']) . ',galaxy,illustration';
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><?= $title ?> &middot; Comics Hub</title>
  <link rel="stylesheet" href="/comics/assets/css/site.css">
</head>
<body>
  <nav class="navbar">
    <div class="navbar__brand">COMICS HUB</div>
    <div class="navbar__links">
      <a href="/comics">All Comics</a>
      <a href="/comics/<?= $slug ?>" style="color:var(--accent);">Overview</a>
      <a href="/ping">Health Check</a>
    </div>
  </nav>

  <header class="hero hero--detail" style="background-image:linear-gradient(135deg, rgba(15,23,42,0.78), rgba(59,130,246,0.18)), url('<?= $thumbUrl ?>'); background-size:cover; background-position:center;">
    <div class="hero__content detail-header">
      <nav class="breadcrumbs">
        <a href="/comics">Comics</a>
        <span>&rsaquo;</span>
        <span><?= $title ?></span>
      </nav>
      <h1 class="hero__title"><?= $title ?></h1>
      <p class="hero__subtitle"><?= $description ?></p>
      <div class="tag-cloud">
        <span class="tag"><?= $chapterTotal ?> chapter<?= $chapterTotal === 1 ? '' : 's' ?></span>
        <span class="tag">AWS-Powered</span>
        <span class="tag">PHP + MySQL</span>
      </div>
      <div class="hero__actions">
        <a class="btn btn--primary" href="/comics/<?= $slug ?>/1">Start reading</a>
        <a class="btn btn--ghost" href="/comics">Back to catalog</a>
      </div>
    </div>
  </header>

  <main class="container">
    <section class="panel">
      <h2 class="section-title">Chapters</h2>
      <?php if (empty($chapters)): ?>
        <p>No chapters published yet. Check back soon!</p>
      <?php else: ?>
        <ul class="chapter-list">
          <?php foreach ($chapters as $chapter): ?>
            <?php
              $number = (int) $chapter['chapter_number'];
              $chapterTitle = htmlspecialchars($chapter['title'], ENT_QUOTES, 'UTF-8');
            ?>
            <li class="chapter-item">
              <div>
                <div class="chapter-item__title">Chapter <?= $number ?> &bull; <?= $chapterTitle ?></div>
                <div style="color:rgba(226,232,240,0.6); font-size:0.85rem; margin-top:0.35rem;">Runtime &middot; Crafted for immersive reading</div>
              </div>
              <a class="btn btn--primary" style="padding:0.55rem 1.1rem; font-size:0.85rem;" href="/comics/<?= $slug ?>/<?= $number ?>">View chapter</a>
            </li>
          <?php endforeach; ?>
        </ul>
      <?php endif; ?>
    </section>
  </main>

  <footer>
    &copy; <?= date('Y') ?> Comics Hub. Stories served from Amazon EC2 + RDS.
  </footer>
</body>
</html>
PHP

cat <<'PHP' >"${APP_ROOT}/lib/views/chapter.php"
<?php
  $comicTitle = htmlspecialchars($comic['title'], ENT_QUOTES, 'UTF-8');
  $slug = htmlspecialchars($comic['slug'], ENT_QUOTES, 'UTF-8');
  $chapterNumber = (int) $chap['chapter_number'];
  $chapterTitle = htmlspecialchars($chap['title'], ENT_QUOTES, 'UTF-8');
  $pageTotal = count($pages);
  $heroArt = 'https://source.unsplash.com/1200x600/?' . rawurlencode($comic['slug'] . ' chapter ' . $chapterNumber) . ',neon,clouds';
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><?= $comicTitle ?> &mdash; Chapter <?= $chapterNumber ?></title>
  <link rel="stylesheet" href="/comics/assets/css/site.css">
</head>
<body>
  <nav class="navbar">
    <div class="navbar__brand">COMICS HUB</div>
    <div class="navbar__links">
      <a href="/comics">Home</a>
      <a href="/comics/<?= $slug ?>">Overview</a>
      <span style="color:var(--accent);">Chapter <?= $chapterNumber ?></span>
    </div>
  </nav>

  <header class="hero hero--detail" style="background-image:linear-gradient(135deg, rgba(15,23,42,0.82), rgba(244,114,182,0.18)), url('<?= $heroArt ?>'); background-size:cover; background-position:center;">
    <div class="hero__content detail-header">
      <nav class="breadcrumbs">
        <a href="/comics">Comics</a>
        <span>&rsaquo;</span>
        <a href="/comics/<?= $slug ?>"><?= $comicTitle ?></a>
        <span>&rsaquo;</span>
        <span>Chapter <?= $chapterNumber ?></span>
      </nav>
      <h1 class="hero__title"><?= $comicTitle ?> &mdash; Chapter <?= $chapterNumber ?></h1>
      <p class="hero__subtitle"><?= $chapterTitle ?>. Immerse yourself in cinematic panels rendered directly from your AWS-powered stack.</p>
      <div class="tag-cloud">
        <span class="tag"><?= $pageTotal ?> page<?= $pageTotal === 1 ? '' : 's' ?></span>
        <span class="tag">High availability</span>
        <span class="tag">Auto Scaling ready</span>
      </div>
      <div class="hero__actions">
        <a class="btn btn--ghost" href="/comics/<?= $slug ?>">Back to chapters</a>
      </div>
    </div>
  </header>

  <main class="container">
    <?php if (empty($pages)): ?>
      <section class="panel">
        <p>No pages published yet. Stay tuned for updates!</p>
      </section>
    <?php else: ?>
      <section class="panel">
        <h2 class="section-title">Chapter gallery</h2>
        <div class="page-gallery">
          <?php foreach ($pages as $page): ?>
            <?php
              $pageNumber = (int) $page['page_number'];
              $path = htmlspecialchars($page['image_path'], ENT_QUOTES, 'UTF-8');
            ?>
            <article class="page-card">
              <img src="/comics/<?= $path ?>" alt="<?= $comicTitle ?> page <?= $pageNumber ?>">
              <div class="page-card__meta">Page <?= $pageNumber ?> &middot; Rendered from <?= $path ?></div>
            </article>
          <?php endforeach; ?>
        </div>
      </section>
    <?php endif; ?>
  </main>

  <footer>
    &copy; <?= date('Y') ?> Comics Hub. Powered by PHP, Apache, and Amazon RDS.
  </footer>
</body>
</html>
PHP

cat <<'CSS' >"${APP_ROOT}/assets/css/site.css"
:root {
  --bg-gradient: linear-gradient(135deg, #0f172a 0%, #1e1b4b 35%, #4c1d95 70%, #7c3aed 100%);
  --card-bg: rgba(15, 23, 42, 0.72);
  --card-hover: rgba(59, 130, 246, 0.18);
  --panel-bg: rgba(15, 23, 42, 0.55);
  --text-primary: #f8fafc;
  --text-secondary: #cbd5f5;
  --accent: #f472b6;
  --accent-strong: #22d3ee;
  --shadow-xl: 0 30px 60px rgba(15, 23, 42, 0.55);
  --shadow-card: 0 25px 40px rgba(15, 23, 42, 0.35);
  --transition-base: all 220ms ease;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  font-family: 'Segoe UI', 'Rubik', 'Inter', system-ui, -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
  background: var(--bg-gradient);
  color: var(--text-primary);
}
a { color: inherit; text-decoration: none; }
a:hover { text-decoration: none; }
.container { width: min(1100px, 92vw); margin: 0 auto; }
.navbar {
  position: sticky; top: 0; z-index: 30; display: flex; justify-content: space-between; align-items: center;
  padding: 1.15rem 5vw; background: rgba(15, 23, 42, 0.55); backdrop-filter: blur(12px);
  border-bottom: 1px solid rgba(148, 163, 184, 0.15);
}
.navbar__brand { font-weight: 700; font-size: 1.1rem; letter-spacing: 0.12rem; text-transform: uppercase; }
.navbar__links { display: flex; gap: 1.5rem; font-size: 0.95rem; color: var(--text-secondary); }
.navbar__links a { position: relative; padding-bottom: 0.25rem; }
.navbar__links a::after {
  content: ''; position: absolute; left: 0; bottom: 0; width: 100%; height: 2px;
  background: linear-gradient(90deg, var(--accent), var(--accent-strong)); opacity: 0; transform: translateY(4px);
  transition: var(--transition-base);
}
.navbar__links a:hover::after { opacity: 1; transform: translateY(0); }
.hero {
  position: relative; overflow: hidden; padding: clamp(3.5rem, 12vw, 6rem) 5vw;
  background: radial-gradient(circle at 10% 20%, rgba(34, 211, 238, 0.25), transparent 55%),
              radial-gradient(circle at 90% 0%, rgba(244, 114, 182, 0.22), transparent 52%);
}
.hero__content { max-width: 580px; display: grid; gap: 1.35rem; z-index: 2; position: relative; }
.hero__badge {
  display: inline-flex; align-items: center; gap: 0.55rem; padding: 0.45rem 1rem;
  background: rgba(30, 64, 175, 0.4); border-radius: 999px; color: var(--accent-strong);
  font-size: 0.85rem; font-weight: 600; letter-spacing: 0.06rem; text-transform: uppercase;
}
.hero__title { font-size: clamp(2.4rem, 5vw, 3.4rem); line-height: 1.1; font-weight: 700; }
.hero__subtitle { color: var(--text-secondary); font-size: 1.05rem; line-height: 1.6; max-width: 34ch; }
.hero__actions { display: flex; flex-wrap: wrap; gap: 0.9rem; }
.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 0.45rem;
  padding: 0.75rem 1.3rem; border-radius: 999px; font-weight: 600; font-size: 0.95rem; transition: var(--transition-base);
  border: 1px solid transparent;
}
.btn--primary {
  background: linear-gradient(135deg, #3b82f6 0%, #6366f1 100%);
  color: var(--text-primary); box-shadow: 0 18px 30px rgba(99, 102, 241, 0.35);
}
.btn--primary:hover { transform: translateY(-2px); box-shadow: 0 22px 38px rgba(99, 102, 241, 0.4); }
.btn--ghost { color: var(--text-secondary); border-color: rgba(226, 232, 240, 0.35); background: rgba(15, 23, 42, 0.25); }
.btn--ghost:hover { color: var(--text-primary); border-color: rgba(148, 163, 184, 0.65); }
.hero__cloud {
  position: absolute; inset: auto 5% -40px 45%; width: 360px; height: 360px;
  background: radial-gradient(circle at 30% 30%, rgba(59, 130, 246, 0.3), transparent 60%),
              radial-gradient(circle at 70% 70%, rgba(139, 92, 246, 0.28), transparent 60%);
  filter: drop-shadow(0 40px 70px rgba(15, 23, 42, 0.5)); opacity: 0.85; border-radius: 50%;
}
main { flex: 1 1 auto; padding: 2.5rem 0 3.5rem; }
.section-title { margin: 0 0 1.5rem; font-size: 1.7rem; font-weight: 650; letter-spacing: 0.03em; }
.comic-grid { display: grid; gap: 1.8rem; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); }
.comic-card {
  background: var(--card-bg); border-radius: 20px; overflow: hidden; padding-bottom: 1.4rem;
  display: flex; flex-direction: column; box-shadow: var(--shadow-card);
  border: 1px solid rgba(148, 163, 184, 0.08); transition: var(--transition-base);
}
.comic-card:hover {
  transform: translateY(-10px); border-color: rgba(34, 211, 238, 0.35);
  box-shadow: 0 35px 45px rgba(30, 64, 175, 0.35); background: var(--card-hover);
}
.comic-card__thumb { height: 180px; background-size: cover; background-position: center; }
.comic-card__body { padding: 1.35rem 1.5rem 0; display: flex; flex-direction: column; gap: 0.7rem; }
.comic-card__title { font-size: 1.25rem; font-weight: 600; }
.comic-card__description { color: var(--text-secondary); font-size: 0.95rem; line-height: 1.55; min-height: 60px; }
.meta-row { display: flex; flex-wrap: wrap; gap: 0.6rem; color: rgba(226, 232, 240, 0.7); font-size: 0.85rem; }
.status-pill {
  padding: 0.25rem 0.7rem; border-radius: 999px; background: rgba(34, 211, 238, 0.18);
  color: var(--accent-strong); font-weight: 600; font-size: 0.8rem; letter-spacing: 0.05em;
}
.panel {
  margin-top: 2.5rem; background: var(--panel-bg); border-radius: 18px; padding: 2rem;
  border: 1px solid rgba(148, 163, 184, 0.12); box-shadow: var(--shadow-card);
}
.chapter-list { list-style: none; padding: 0; margin: 0; display: grid; gap: 1rem; }
.chapter-item {
  display: flex; justify-content: space-between; align-items: center;
  padding: 1rem 1.2rem; border-radius: 14px; background: rgba(15, 23, 42, 0.46);
  border: 1px solid rgba(148, 163, 184, 0.12); transition: var(--transition-base);
}
.chapter-item:hover { border-color: rgba(34, 211, 238, 0.35); transform: translateY(-4px); }
.chapter-item__title { font-weight: 600; }
.breadcrumbs { display: flex; gap: 0.6rem; font-size: 0.85rem; margin-bottom: 1rem; color: rgba(226, 232, 240, 0.65); }
.breadcrumbs a { color: var(--accent-strong); font-weight: 600; }
.hero--detail { padding: clamp(2.8rem, 9vw, 4.8rem) 5vw; }
.detail-header { display: grid; gap: 1.2rem; max-width: 760px; }
.tag-cloud { display: flex; gap: 0.6rem; flex-wrap: wrap; }
.tag { padding: 0.35rem 0.85rem; background: rgba(59, 130, 246, 0.22); border-radius: 999px; font-size: 0.8rem; letter-spacing: 0.04em; }
.page-gallery { display: grid; gap: 1.5rem; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); margin-top: 1.5rem; }
.page-card {
  background: rgba(15, 23, 42, 0.6); border-radius: 18px; overflow: hidden;
  border: 1px solid rgba(148, 163, 184, 0.12); box-shadow: var(--shadow-card);
  transition: var(--transition-base);
}
.page-card:hover { transform: translateY(-6px); border-color: rgba(244, 114, 182, 0.45); }
.page-card img { width: 100%; display: block; }
.page-card__meta { padding: 1rem 1.3rem 1.2rem; color: rgba(226, 232, 240, 0.75); font-size: 0.85rem; }
footer {
  margin-top: auto; padding: 2rem 5vw 2.5rem; background: rgba(15, 23, 42, 0.55);
  border-top: 1px solid rgba(148, 163, 184, 0.12); color: rgba(226, 232, 240, 0.6);
  font-size: 0.85rem; text-align: center;
}
@media (max-width: 720px) {
  .navbar { flex-direction: column; gap: 0.75rem; }
  .hero__actions { width: 100%; justify-content: center; }
  .chapter-item { flex-direction: column; align-items: flex-start; gap: 0.75rem; }
}
CSS

cat <<'HT' >"${APP_ROOT}/.htaccess"
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ index.php [QSA,L]
HT

for i in 1 2 3; do
  echo "Page $i" >"${UPLOAD_DIR}/${i}.jpg"
done

cat <<ENVFILE >/etc/profile.d/app-env.sh
export DB_HOST="${RDS_HOST}"
export DB_USER="${RDS_USER}"
export DB_PASS="${RDS_PASS}"
export DB_NAME="${RDS_DB}"
ENVFILE

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

mysql_ready() {
  mysql -h "${RDS_HOST}" -u "${RDS_USER}" -p"${RDS_PASS}" -e "SELECT 1" >/dev/null 2>&1
}

until mysql_ready; do
  echo "[user-data] Waiting for RDS endpoint ${RDS_HOST}..."
  sleep 15
done

cat <<SQL >/tmp/comics_seed.sql
USE ${RDS_DB};
CREATE TABLE IF NOT EXISTS comics (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL UNIQUE,
  description TEXT
);
CREATE TABLE IF NOT EXISTS chapters (
  id INT AUTO_INCREMENT PRIMARY KEY,
  comic_id INT NOT NULL,
  chapter_number INT NOT NULL,
  title VARCHAR(255) NOT NULL,
  UNIQUE KEY uniq_chapter (comic_id, chapter_number),
  FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS pages (
  id INT AUTO_INCREMENT PRIMARY KEY,
  chapter_id INT NOT NULL,
  page_number INT NOT NULL,
  image_path VARCHAR(255) NOT NULL,
  UNIQUE KEY uniq_page (chapter_id, page_number),
  FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE
);
INSERT INTO comics (title, slug, description) VALUES
  ('Galactic Adventures', 'galactic-adventures', 'Follow Captain Nova across the stars.'),
  ('Mystic Realms', 'mystic-realms', 'A saga of magic, myths, and monsters.')
ON DUPLICATE KEY UPDATE title = VALUES(title), description = VALUES(description);
INSERT INTO chapters (comic_id, chapter_number, title)
  SELECT id, 1, 'First Contact' FROM comics WHERE slug = 'galactic-adventures'
ON DUPLICATE KEY UPDATE title = VALUES(title);
INSERT INTO chapters (comic_id, chapter_number, title)
  SELECT id, 1, 'Awakening' FROM comics WHERE slug = 'mystic-realms'
ON DUPLICATE KEY UPDATE title = VALUES(title);
INSERT INTO pages (chapter_id, page_number, image_path)
  SELECT c.id, 1, 'uploads/sample/1.jpg'
  FROM chapters c JOIN comics co ON c.comic_id = co.id
  WHERE co.slug = 'galactic-adventures' AND c.chapter_number = 1
ON DUPLICATE KEY UPDATE image_path = VALUES(image_path);
INSERT INTO pages (chapter_id, page_number, image_path)
  SELECT c.id, 2, 'uploads/sample/2.jpg'
  FROM chapters c JOIN comics co ON c.comic_id = co.id
  WHERE co.slug = 'galactic-adventures' AND c.chapter_number = 1
ON DUPLICATE KEY UPDATE image_path = VALUES(image_path);
INSERT INTO pages (chapter_id, page_number, image_path)
  SELECT c.id, 1, 'uploads/sample/3.jpg'
  FROM chapters c JOIN comics co ON c.comic_id = co.id
  WHERE co.slug = 'mystic-realms' AND c.chapter_number = 1
ON DUPLICATE KEY UPDATE image_path = VALUES(image_path);
SQL

mysql -h "${RDS_HOST}" -u "${RDS_USER}" -p"${RDS_PASS}" < /tmp/comics_seed.sql
rm -f /tmp/comics_seed.sql

systemctl restart httpd

curl -fsS http://127.0.0.1/comics/ | head -n 40 || true

systemctl status httpd --no-pager || true

echo "[user-data] Completed at $(date --iso-8601=seconds)"
