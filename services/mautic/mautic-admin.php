<?php
/*
 * Keep the Mautic admin password equal to MAUTIC_ADMIN_PASSWORD (read from
 * stdin). Updates the stored hash only when the password does not match, so
 * a redeploy with an unchanged variable changes nothing.
 */
declare(strict_types=1);

function railway_log(string $message): void
{
    fwrite(STDOUT, gmdate('Y-m-d\TH:i:s\Z') . " railway-admin: $message\n");
}

$password = (string) stream_get_contents(STDIN);
$username = (string) getenv('RW_USERNAME');
$prefix   = '';
$local    = '/var/www/html/config/local.php';
if (is_readable($local)) {
    $parameters = [];
    include $local;
    $prefix = (string) ($parameters['db_table_prefix'] ?? '');
}

try {
    $pdo = new PDO(
        sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4', getenv('MAUTIC_DB_HOST'), getenv('MAUTIC_DB_PORT') ?: '3306', getenv('MAUTIC_DB_NAME')),
        (string) getenv('MAUTIC_DB_USER'),
        (string) getenv('MAUTIC_DB_PASSWORD'),
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 5]
    );
    $table = $prefix . 'users';
    $stmt  = $pdo->prepare("SELECT id, password FROM `$table` WHERE username = ?");
    $stmt->execute([$username]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (false === $row) {
        railway_log("no user '$username' (MAUTIC_ADMIN_USERNAME); nothing changed");
        exit(0);
    }
    if (password_verify($password, (string) $row['password'])) {
        railway_log("password of '$username' matches MAUTIC_ADMIN_PASSWORD");
        exit(0);
    }
    $update = $pdo->prepare("UPDATE `$table` SET password = ? WHERE id = ?");
    $update->execute([password_hash($password, PASSWORD_BCRYPT, ['cost' => 13]), $row['id']]);
    railway_log("password of '$username' changed to MAUTIC_ADMIN_PASSWORD");
} catch (Throwable $e) {
    railway_log('ERROR: ' . $e->getMessage());
    exit(1);
}
