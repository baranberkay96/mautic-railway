<?php
/*
 * Railway healthcheck for Mautic: 200 when Mautic is installed and MySQL
 * answers. Served by Apache at /railway-healthz outside the docroot (Mautic's
 * .htaccess denies PHP files there, and its own pages redirect plain-HTTP
 * requests to the https site URL).
 */
declare(strict_types=1);

header('Content-Type: text/plain');
header('Cache-Control: no-store');
$parameters = [];
if (is_readable('/var/www/html/config/local.php')) {
    include '/var/www/html/config/local.php';
}
if (empty($parameters['db_driver']) || empty($parameters['site_url'])) {
    http_response_code(503);
    exit("not installed\n");
}
try {
    $pdo = new PDO(
        sprintf('mysql:host=%s;port=%s;dbname=%s', getenv('MAUTIC_DB_HOST'), getenv('MAUTIC_DB_PORT') ?: '3306', getenv('MAUTIC_DB_NAME')),
        (string) getenv('MAUTIC_DB_USER'),
        (string) getenv('MAUTIC_DB_PASSWORD'),
        [PDO::ATTR_TIMEOUT => 3, PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $pdo->query('SELECT 1');
} catch (Throwable $e) {
    http_response_code(503);
    exit("database unavailable\n");
}
echo "ok\n";
