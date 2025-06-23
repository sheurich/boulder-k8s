CREATE USER IF NOT EXISTS 'sa_ro'@'%' IDENTIFIED BY 'example-sa-password';
GRANT ALL PRIVILEGES ON boulder_sa_integration.* TO 'sa_ro'@'%';
FLUSH PRIVILEGES;
