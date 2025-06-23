CREATE USER IF NOT EXISTS 'incidents_sa'@'%' IDENTIFIED BY 'example-sa-password';
GRANT ALL PRIVILEGES ON incidents_sa_integration.* TO 'incidents_sa'@'%';
FLUSH PRIVILEGES;
