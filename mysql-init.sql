CREATE DATABASE IF NOT EXISTS mailserver;
USE mailserver;

-- Domains table
CREATE TABLE IF NOT EXISTS virtual_domains (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    active BOOLEAN DEFAULT TRUE
);

-- Users table
CREATE TABLE IF NOT EXISTS virtual_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    domain_id INT NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    quota BIGINT DEFAULT 10485760,
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
);

-- Aliases table
CREATE TABLE IF NOT EXISTS virtual_aliases (
    id INT AUTO_INCREMENT PRIMARY KEY,
    domain_id INT NOT NULL,
    source VARCHAR(255) NOT NULL,
    destination VARCHAR(255) NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
);

-- Insert default domain
INSERT IGNORE INTO virtual_domains (name) VALUES ('system.syscomatic.com');

-- Insert admin user with encrypted password
INSERT IGNORE INTO virtual_users (domain_id, email, password) 
VALUES (
    1, 
    'admin@system.syscomatic.com', 
    '{SHA512-CRYPT}$6$rounds=656000$yourtokenhere$yourtokenhere'
);

-- Insert test user
INSERT IGNORE INTO virtual_users (domain_id, email, password) 
VALUES (
    1, 
    'test@system.syscomatic.com', 
    '{PLAIN}TestPass123!'
);

-- Insert common aliases
INSERT IGNORE INTO virtual_aliases (domain_id, source, destination) VALUES
(1, 'postmaster@system.syscomatic.com', 'admin@system.syscomatic.com'),
(1, 'abuse@system.syscomatic.com', 'admin@system.syscomatic.com'),
(1, 'webmaster@system.syscomatic.com', 'admin@system.syscomatic.com'),
(1, 'hostmaster@system.syscomatic.com', 'admin@system.syscomatic.com');