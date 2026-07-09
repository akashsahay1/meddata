/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19-12.3.2-MariaDB, for osx10.19 (x86_64)
--
-- Host: localhost    Database: med_stock
-- ------------------------------------------------------
-- Server version	12.3.2-MariaDB

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*M!100616 SET @OLD_NOTE_VERBOSITY=@@NOTE_VERBOSITY, NOTE_VERBOSITY=0 */;

--
-- Table structure for table `app_settings`
--

DROP TABLE IF EXISTS `app_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `app_settings` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) NOT NULL,
  `value` text DEFAULT NULL,
  `type` varchar(255) NOT NULL DEFAULT 'string',
  `label` varchar(255) DEFAULT NULL,
  `group` varchar(255) NOT NULL DEFAULT 'general',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `app_settings_key_unique` (`key`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `app_settings`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `app_settings` WRITE;
/*!40000 ALTER TABLE `app_settings` DISABLE KEYS */;
INSERT INTO `app_settings` VALUES
(1,'free_tier_limit','7','int','Free tier medicine limit','limits','2026-07-04 04:34:59','2026-07-04 04:34:59'),
(2,'expiry_warning_days','30','int','Default expiry warning (days)','alerts','2026-07-04 04:34:59','2026-07-04 04:34:59'),
(3,'low_stock_default','10','int','Default low-stock threshold','alerts','2026-07-04 04:34:59','2026-07-04 04:34:59'),
(4,'support_email','akash.sahay1@gmail.com','string','Support email','general','2026-07-04 04:34:59','2026-07-04 04:34:59'),
(5,'maintenance_mode','0','bool','Maintenance mode','general','2026-07-04 04:34:59','2026-07-04 04:34:59'),
(6,'force_update','0','bool','Force app update','general','2026-07-04 04:34:59','2026-07-04 04:34:59');
/*!40000 ALTER TABLE `app_settings` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `backups`
--

DROP TABLE IF EXISTS `backups`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `backups` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `device_id` varchar(255) NOT NULL,
  `user_id` bigint(20) unsigned DEFAULT NULL,
  `path` varchar(255) NOT NULL,
  `size` bigint(20) unsigned NOT NULL DEFAULT 0,
  `medicine_count` int(10) unsigned NOT NULL DEFAULT 0,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `backups_user_id_foreign` (`user_id`),
  KEY `backups_device_id_index` (`device_id`),
  CONSTRAINT `backups_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `backups`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `backups` WRITE;
/*!40000 ALTER TABLE `backups` DISABLE KEYS */;
/*!40000 ALTER TABLE `backups` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `cache`
--

DROP TABLE IF EXISTS `cache`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cache` (
  `key` varchar(255) NOT NULL,
  `value` mediumtext NOT NULL,
  `expiration` bigint(20) NOT NULL,
  PRIMARY KEY (`key`),
  KEY `cache_expiration_index` (`expiration`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `cache`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `cache` WRITE;
/*!40000 ALTER TABLE `cache` DISABLE KEYS */;
/*!40000 ALTER TABLE `cache` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `cache_locks`
--

DROP TABLE IF EXISTS `cache_locks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cache_locks` (
  `key` varchar(255) NOT NULL,
  `owner` varchar(255) NOT NULL,
  `expiration` bigint(20) NOT NULL,
  PRIMARY KEY (`key`),
  KEY `cache_locks_expiration_index` (`expiration`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `cache_locks`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `cache_locks` WRITE;
/*!40000 ALTER TABLE `cache_locks` DISABLE KEYS */;
/*!40000 ALTER TABLE `cache_locks` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `customers`
--

DROP TABLE IF EXISTS `customers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `customers` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `email` varchar(255) NOT NULL,
  `phone` varchar(255) DEFAULT NULL,
  `city` varchar(255) DEFAULT NULL,
  `state` varchar(255) DEFAULT NULL,
  `status` enum('active','inactive','blocked') NOT NULL DEFAULT 'active',
  `plan_id` bigint(20) unsigned DEFAULT NULL,
  `device_id` varchar(255) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `customers_email_unique` (`email`),
  KEY `customers_plan_id_foreign` (`plan_id`),
  CONSTRAINT `customers_plan_id_foreign` FOREIGN KEY (`plan_id`) REFERENCES `plans` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=31 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `customers`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `customers` WRITE;
/*!40000 ALTER TABLE `customers` DISABLE KEYS */;
INSERT INTO `customers` VALUES
(1,'Aishwarya Shere','customer1.l9dm@example.com','9160157705','Hyderabad','Telangana','active',1,'83b7f327-a7b8-4f87-b39d-e6ac0de6ee01',NULL,'2025-12-12 12:21:54','2026-07-04 04:35:00',NULL),
(2,'Amir Bhatti','customer2.sgth@example.com','9965625310','Bhubaneswar','Odisha','active',1,'72b2b138-752b-457e-8156-e7e59ce5fed8',NULL,'2026-01-03 12:21:54','2026-07-04 04:35:00',NULL),
(3,'Srinivasan Comar','customer3.gzmh@example.com','9996455818','Bhubaneswar','Odisha','inactive',1,'64ec5ef7-3010-4111-a5ef-527829011d30',NULL,'2026-05-05 12:21:54','2026-07-04 04:35:00',NULL),
(4,'Suraj Ujwal Dube','customer4.pgbf@example.com','9264029593','Chennai','Tamil Nadu','active',1,'6b7fc36b-da04-4705-b92c-e65b7bb605bd','Quo enim qui nisi incidunt.','2025-11-15 12:21:54','2026-07-04 04:35:00',NULL),
(5,'Monica Mani','customer5.wcjl@example.com','9892558125','Delhi','Delhi','active',4,'95e62096-0452-4ad0-9c6e-c278cca2311d',NULL,'2026-06-15 12:21:54','2026-07-04 04:35:00',NULL),
(6,'Farah Vyas','customer6.jmng@example.com','9646921286','Bhubaneswar','Odisha','blocked',3,'815a575e-3649-4c11-966e-81d9251ecee4',NULL,'2026-03-07 12:21:54','2026-07-04 04:35:00',NULL),
(7,'Sunita Lalit Nori','customer7.sgzp@example.com','9313371913','Kolkata','West Bengal','inactive',3,'3ef6a23a-99f9-4b75-a389-d0805edc6964',NULL,'2026-05-06 12:21:54','2026-07-04 04:35:00',NULL),
(8,'Rita Bava','customer8.5xae@example.com','9521578630','Jaipur','Rajasthan','inactive',2,'db300e65-3302-4499-b9a3-c9b558aa9e29','Dolorem quo rerum saepe itaque dignissimos aspernatur ratione.','2026-01-04 12:21:54','2026-07-04 04:35:00',NULL),
(9,'Devendra Chandra Vyas','customer9.hhuw@example.com','9615631696','Mumbai','Maharashtra','active',1,'0f98f1d0-ea16-45f1-8486-acce68f73b56',NULL,'2026-06-27 12:21:54','2026-07-04 04:35:00',NULL),
(10,'Biren Bhola Sridhar','customer10.b7z2@example.com','9001327465','Ahmedabad','Gujarat','active',2,'a208f82e-f79a-439a-99d7-535f5feffbf5',NULL,'2025-12-05 12:21:54','2026-07-04 04:35:00',NULL),
(11,'Hetan Divan','customer11.6zvq@example.com','9333010227','Mumbai','Maharashtra','inactive',3,'91ab6c22-15f4-4934-8efc-b1f38b8eabb5',NULL,'2026-04-20 12:21:54','2026-07-04 04:35:00',NULL),
(12,'Rupesh Bhai Chia','customer12.tsow@example.com','9408013999','Delhi','Delhi','active',3,'b69ed3c1-6f90-44d5-bcac-58656a9da2b8','Et beatae quia sit placeat ut ut.','2025-11-22 12:21:54','2026-07-04 04:35:00',NULL),
(13,'Diya Bobal','customer13.w76f@example.com','9137426020','Chennai','Tamil Nadu','inactive',4,'30763742-8240-4966-a3db-2a55a372ce22',NULL,'2026-01-11 12:21:54','2026-07-04 04:35:00',NULL),
(14,'Ekbal Fakaruddin Usman','customer14.smvv@example.com','9849937452','Delhi','Delhi','active',1,'bfc82086-0ca9-4a85-bd82-6f62221c403b',NULL,'2025-12-17 12:21:54','2026-07-04 04:35:00',NULL),
(15,'Indira Subramaniam','customer15.avjo@example.com','9570589649','Chennai','Tamil Nadu','inactive',4,'cdcaf1d7-40f4-442e-9ed5-b706760261cd',NULL,'2025-11-12 12:21:54','2026-07-04 04:35:00',NULL),
(16,'Javed Fardeen Lall','customer16.97xz@example.com','9605458954','Ahmedabad','Gujarat','active',2,'26d616f8-bc8f-40ec-932d-bd835080f17a','Enim autem expedita qui architecto.','2026-04-01 12:21:54','2026-07-04 04:35:00',NULL),
(17,'Sahil Somani','customer17.aykb@example.com','9529514074','Chennai','Tamil Nadu','blocked',2,'51c1bae7-a227-40f6-9b7c-576710cbc970',NULL,'2026-06-26 12:21:54','2026-07-04 04:35:00',NULL),
(18,'Tanay Soni','customer18.wb3m@example.com','9674963400','Patna','Bihar','blocked',3,'b44eadd7-0f17-492b-871d-9a1d64682d3e',NULL,'2025-11-07 12:21:54','2026-07-04 04:35:00',NULL),
(19,'Qadim Mangal','customer19.5apl@example.com','9153043565','Delhi','Delhi','active',3,'b3217e3c-d239-4d6c-a331-1e6bcd151c88',NULL,'2025-12-07 12:21:54','2026-07-04 04:35:00',NULL),
(20,'Zahir Rao Datta','customer20.bmfp@example.com','9722506520','Bengaluru','Karnataka','active',2,'08d1e2f3-d575-43dc-bc76-951fb3d5c9a6','Dicta vitae enim repellat et facere voluptatem.','2026-04-05 12:21:54','2026-07-04 04:35:00',NULL),
(21,'Abhishek Surya Dhar','customer21.hp9s@example.com','9930914743','Hyderabad','Telangana','active',3,'1b257f41-976f-408c-800f-9bb85712cd26',NULL,'2026-04-30 12:21:54','2026-07-04 04:35:00',NULL),
(22,'Iqbal Kalyan Dewan','customer22.l1bw@example.com','9292673071','Hyderabad','Telangana','blocked',1,'7ccf27ca-f0e2-4faa-b39d-048cea07a1a1',NULL,'2026-05-13 12:21:54','2026-07-04 04:35:00',NULL),
(23,'Aadil Chia','customer23.fkdb@example.com','9054379946','Bengaluru','Karnataka','active',1,'50f3453c-84a2-4482-8d6f-653687986410',NULL,'2026-04-26 12:21:54','2026-07-04 04:35:00',NULL),
(24,'Aditya Chand Dhingra','customer24.juev@example.com','9498875160','Jaipur','Rajasthan','inactive',1,'99119e5e-350c-46cf-af78-d7ca8c9388c8','Pariatur voluptate corporis quod beatae ipsa quasi.','2025-12-28 12:21:54','2026-07-04 04:35:00',NULL),
(25,'Somnath Bandi','customer25.fnww@example.com','9770370248','Pune','Maharashtra','active',3,'d1044a7d-7331-47fa-a50b-394dae9ab69f',NULL,'2026-06-20 12:21:54','2026-07-04 04:35:00',NULL),
(26,'Atul Sumit Nagarajan','customer26.sy5o@example.com','9032240291','Delhi','Delhi','active',1,'0f341e23-c6eb-4997-a57c-acaa9647ce32',NULL,'2025-11-18 12:21:54','2026-07-04 04:35:00',NULL),
(27,'Hetan Pratap Sood','customer27.tk3b@example.com','9876745630','Jaipur','Rajasthan','inactive',1,'2af718cf-226b-4b39-b360-cdf1f446b7af',NULL,'2026-02-16 12:21:54','2026-07-04 04:35:00',NULL),
(28,'Suresh Rao Tailor','customer28.ejtn@example.com','9275485238','Kolkata','West Bengal','active',3,'8b98391e-ed5b-4be2-8bd4-d789f807c652','Esse dolor tenetur quibusdam molestias unde dolor.','2026-06-27 12:21:54','2026-07-04 04:35:00',NULL),
(29,'Ritika Varma','customer29.nuts@example.com','9632736746','Kolkata','West Bengal','active',4,'45fa58e8-3ebf-488f-a0aa-6b74250d1dd4',NULL,'2026-03-24 12:21:54','2026-07-04 04:35:00',NULL),
(30,'Fatima Muni','customer30.efkj@example.com','9103703880','Bhubaneswar','Odisha','active',2,'5fea18d8-1e8f-4dbe-9953-2a5eac776a55',NULL,'2026-06-26 12:21:54','2026-07-04 04:35:00',NULL);
/*!40000 ALTER TABLE `customers` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `devices`
--

DROP TABLE IF EXISTS `devices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `devices` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `device_id` varchar(255) NOT NULL,
  `user_id` bigint(20) unsigned DEFAULT NULL,
  `platform` varchar(255) NOT NULL DEFAULT 'android',
  `app_version` varchar(255) DEFAULT NULL,
  `last_seen_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `devices_device_id_unique` (`device_id`),
  KEY `devices_user_id_foreign` (`user_id`),
  CONSTRAINT `devices_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `devices`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `devices` WRITE;
/*!40000 ALTER TABLE `devices` DISABLE KEYS */;
/*!40000 ALTER TABLE `devices` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `entitlements`
--

DROP TABLE IF EXISTS `entitlements`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `entitlements` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `device_id` varchar(255) NOT NULL,
  `plan_id` bigint(20) unsigned DEFAULT NULL,
  `product_id` varchar(255) DEFAULT NULL,
  `status` varchar(255) NOT NULL DEFAULT 'expired',
  `purchase_token` varchar(255) DEFAULT NULL,
  `expiry_time` timestamp NULL DEFAULT NULL,
  `is_premium` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `entitlements_plan_id_foreign` (`plan_id`),
  KEY `entitlements_device_id_status_index` (`device_id`,`status`),
  KEY `entitlements_device_id_index` (`device_id`),
  CONSTRAINT `entitlements_plan_id_foreign` FOREIGN KEY (`plan_id`) REFERENCES `plans` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `entitlements`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `entitlements` WRITE;
/*!40000 ALTER TABLE `entitlements` DISABLE KEYS */;
/*!40000 ALTER TABLE `entitlements` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `failed_jobs`
--

DROP TABLE IF EXISTS `failed_jobs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `failed_jobs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `uuid` varchar(255) NOT NULL,
  `connection` varchar(255) NOT NULL,
  `queue` varchar(255) NOT NULL,
  `payload` longtext NOT NULL,
  `exception` longtext NOT NULL,
  `failed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `failed_jobs_uuid_unique` (`uuid`),
  KEY `failed_jobs_connection_queue_failed_at_index` (`connection`,`queue`,`failed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `failed_jobs`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `failed_jobs` WRITE;
/*!40000 ALTER TABLE `failed_jobs` DISABLE KEYS */;
/*!40000 ALTER TABLE `failed_jobs` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `job_batches`
--

DROP TABLE IF EXISTS `job_batches`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `job_batches` (
  `id` varchar(255) NOT NULL,
  `name` varchar(255) NOT NULL,
  `total_jobs` int(11) NOT NULL,
  `pending_jobs` int(11) NOT NULL,
  `failed_jobs` int(11) NOT NULL,
  `failed_job_ids` longtext NOT NULL,
  `options` mediumtext DEFAULT NULL,
  `cancelled_at` int(11) DEFAULT NULL,
  `created_at` int(11) NOT NULL,
  `finished_at` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `job_batches`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `job_batches` WRITE;
/*!40000 ALTER TABLE `job_batches` DISABLE KEYS */;
/*!40000 ALTER TABLE `job_batches` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `jobs`
--

DROP TABLE IF EXISTS `jobs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `jobs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `queue` varchar(255) NOT NULL,
  `payload` longtext NOT NULL,
  `attempts` smallint(5) unsigned NOT NULL,
  `reserved_at` int(10) unsigned DEFAULT NULL,
  `available_at` int(10) unsigned NOT NULL,
  `created_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `jobs_queue_index` (`queue`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `jobs`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `jobs` WRITE;
/*!40000 ALTER TABLE `jobs` DISABLE KEYS */;
/*!40000 ALTER TABLE `jobs` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `medicines`
--

DROP TABLE IF EXISTS `medicines`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `medicines` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `store_id` bigint(20) unsigned DEFAULT NULL,
  `name` varchar(255) NOT NULL,
  `brand` varchar(255) DEFAULT NULL,
  `category` varchar(255) DEFAULT NULL,
  `batch_no` varchar(255) DEFAULT NULL,
  `barcode` varchar(255) DEFAULT NULL,
  `quantity` int(11) NOT NULL DEFAULT 0,
  `unit` varchar(255) DEFAULT NULL,
  `expiry_date` date DEFAULT NULL,
  `selling_price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `medicines_store_id_foreign` (`store_id`),
  CONSTRAINT `medicines_store_id_foreign` FOREIGN KEY (`store_id`) REFERENCES `stores` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=121 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `medicines`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `medicines` WRITE;
/*!40000 ALTER TABLE `medicines` DISABLE KEYS */;
INSERT INTO `medicines` VALUES
(1,39,'Insulin Glargine','Cipla','Injection','BOJRZZI','6624896455535',1,'vial','2026-07-25',73.11,'2026-02-18 12:21:54','2026-07-04 04:35:00',NULL),
(2,6,'Diclofenac Gel','Sun Pharma','Inhaler','BU0TBFO','2279147964164',223,'vial','2028-07-24',186.16,'2026-05-24 12:21:54','2026-07-04 04:35:00',NULL),
(3,36,'Metformin 500','GSK','Capsule','BMKNJPB','1819123804094',334,'strip','2027-09-22',189.08,'2026-01-29 12:21:54','2026-07-04 04:35:00',NULL),
(4,13,'Betadine Ointment','Alkem','Powder','BTEWLBF','1609130325961',298,'tube','2028-08-28',258.49,'2026-03-06 12:21:54','2026-07-04 04:35:00',NULL),
(5,29,'Cetirizine 10','Alkem','Powder','BOOJ9CX','7593304300509',35,'box','2026-03-19',1056.50,'2026-02-24 12:21:54','2026-07-04 04:35:00',NULL),
(6,29,'Paracetamol 500','Lupin','Drops','BBRTYLF','6829932342323',0,'box','2026-07-05',546.54,'2026-03-13 12:21:54','2026-07-04 04:35:00',NULL),
(7,1,'Vitamin D3','Lupin','Capsule','BBYP8GY','7569939074672',6,'strip','2028-04-12',1231.96,'2026-01-08 12:21:54','2026-07-04 04:35:00',NULL),
(8,35,'Pantoprazole 40','Dr Reddy','Tablet','BN1EXKF','1584717355206',241,'strip','2028-05-09',593.26,'2026-07-01 12:21:54','2026-07-04 04:35:00',NULL),
(9,40,'Paracetamol 500','Abbott','Syrup','BWQOUL9','9969044809202',143,'tube','2028-02-09',764.37,'2026-06-09 12:21:54','2026-07-04 04:35:00',NULL),
(10,38,'Vitamin D3','Abbott','Ointment','B18DYFH','4152731760497',49,'tube','2026-06-03',1126.75,'2026-03-09 12:21:54','2026-07-04 04:35:00',NULL),
(11,8,'Pantoprazole 40','Alkem','Syrup','BUU6K0F','8638384596349',136,'vial','2026-07-20',1435.96,'2026-02-02 12:21:54','2026-07-04 04:35:00',NULL),
(12,40,'B-Complex','Cipla','Ointment','BJ7YJHD','4748567354186',0,'box','2028-10-23',1236.12,'2026-05-17 12:21:54','2026-07-04 04:35:00',NULL),
(13,29,'Ibuprofen 400','GSK','Inhaler','BV2RKEJ','8909246203669',6,'bottle','2027-05-23',688.60,'2026-02-07 12:21:54','2026-07-04 04:35:00',NULL),
(14,21,'Ibuprofen 400','Alkem','Tablet','BRQELZ1','5288298280266',85,'vial','2026-09-28',1379.21,'2026-05-17 12:21:54','2026-07-04 04:35:00',NULL),
(15,23,'Atorvastatin 10','Mankind','Drops','BBI9BXA','3902087127168',71,'bottle','2026-06-10',14.70,'2026-01-24 12:21:54','2026-07-04 04:35:00',NULL),
(16,40,'Pantoprazole 40','Zydus','Injection','BRPAWOD','2311368170396',186,'pack','2026-07-08',302.47,'2026-03-06 12:21:54','2026-07-04 04:35:00',NULL),
(17,35,'Eye Drops Lubricant','Pfizer','Ointment','BTIBYVM','7679969195565',127,'strip','2028-09-02',356.34,'2026-03-09 12:21:54','2026-07-04 04:35:00',NULL),
(18,24,'Amoxicillin 250','Lupin','Drops','BHYYCZV','8144671510535',0,'box','2028-02-16',439.32,'2026-05-18 12:21:54','2026-07-04 04:35:00',NULL),
(19,29,'Salbutamol Inhaler','Zydus','Drops','BORQFWA','3095531659862',5,'tube','2027-04-13',1146.77,'2026-04-30 12:21:54','2026-07-04 04:35:00',NULL),
(20,33,'Pantoprazole 40','Dr Reddy','Inhaler','BQXHFZJ','7932107240672',36,'pack','2026-06-21',591.31,'2026-06-28 12:21:54','2026-07-04 04:35:00',NULL),
(21,12,'ORS Powder','GSK','Powder','BE9PBW4','9925657602449',352,'tube','2026-07-07',368.35,'2026-06-22 12:21:54','2026-07-04 04:35:00',NULL),
(22,16,'Paracetamol 500','Lupin','Capsule','B1S6NLO','1998283221030',191,'pack','2027-06-29',1219.50,'2026-05-21 12:21:54','2026-07-04 04:35:00',NULL),
(23,28,'Omeprazole 20','Lupin','Syrup','BLWU1NP','0939038648987',343,'strip','2028-05-24',526.00,'2026-06-29 12:21:54','2026-07-04 04:35:00',NULL),
(24,26,'Cough Syrup','Mankind','Tablet','BE1SFJ7','2257430238956',0,'tube','2026-10-27',405.09,'2026-04-23 12:21:54','2026-07-04 04:35:00',NULL),
(25,36,'Metformin 500','Dr Reddy','Tablet','BIX164I','8659368391866',2,'vial','2026-07-02',1322.34,'2026-01-18 12:21:54','2026-07-04 04:35:00',NULL),
(26,9,'Omeprazole 20','Pfizer','Inhaler','BIC8BIB','4786824956353',272,'bottle','2026-07-12',1076.79,'2026-04-14 12:21:54','2026-07-04 04:35:00',NULL),
(27,24,'Omeprazole 20','Abbott','Tablet','B0JBAOO','0417426814195',276,'box','2028-01-27',1295.82,'2026-04-13 12:21:54','2026-07-04 04:35:00',NULL),
(28,9,'Pantoprazole 40','GSK','Syrup','BFKMHHE','1085367129631',342,'pack','2027-04-03',557.22,'2026-01-17 12:21:54','2026-07-04 04:35:00',NULL),
(29,16,'Insulin Glargine','Lupin','Powder','BWKKSJM','8785710487021',100,'bottle','2026-10-15',349.34,'2026-05-11 12:21:54','2026-07-04 04:35:00',NULL),
(30,7,'Betadine Ointment','GSK','Tablet','BSSIQ7H','1235820885516',0,'vial','2026-06-17',737.14,'2026-02-25 12:21:54','2026-07-04 04:35:00',NULL),
(31,9,'B-Complex','Dr Reddy','Tablet','BLZE512','0273607931132',4,'bottle','2026-07-27',351.22,'2026-03-04 12:21:54','2026-07-04 04:35:00',NULL),
(32,12,'Ibuprofen 400','Cipla','Tablet','B5PUGAK','4991186554035',182,'vial','2027-04-01',1163.33,'2026-05-20 12:21:54','2026-07-04 04:35:00',NULL),
(33,34,'Amlodipine 5','Dr Reddy','Tablet','BY2NBQC','9726115441996',189,'tube','2026-10-30',828.97,'2026-05-25 12:21:54','2026-07-04 04:35:00',NULL),
(34,17,'Domperidone 10','Dr Reddy','Injection','BVSIE3G','9959573630842',207,'box','2028-05-13',1387.78,'2026-04-30 12:21:54','2026-07-04 04:35:00',NULL),
(35,32,'Insulin Glargine','GSK','Inhaler','B5SMJQJ','8585930943501',318,'vial','2026-03-28',1094.46,'2026-06-10 12:21:54','2026-07-04 04:35:00',NULL),
(36,2,'Vitamin D3','Zydus','Powder','BCB82UC','9253181742691',0,'pack','2026-07-30',363.17,'2026-03-20 12:21:54','2026-07-04 04:35:00',NULL),
(37,27,'Domperidone 10','GSK','Powder','BMHVMPR','1720797323661',3,'vial','2028-04-03',274.44,'2026-03-27 12:21:54','2026-07-04 04:35:00',NULL),
(38,23,'Eye Drops Lubricant','Dr Reddy','Ointment','BHELKG3','0239053623465',197,'bottle','2028-05-26',572.69,'2026-01-06 12:21:54','2026-07-04 04:35:00',NULL),
(39,31,'Insulin Glargine','Zydus','Tablet','BL8QDQ7','0626628121028',24,'pack','2027-09-13',1268.68,'2026-05-06 12:21:54','2026-07-04 04:35:00',NULL),
(40,13,'Amoxicillin 250','Mankind','Powder','BGS6XFI','4475702538766',382,'bottle','2026-06-25',222.74,'2026-03-09 12:21:54','2026-07-04 04:35:00',NULL),
(41,28,'Betadine Ointment','Alkem','Powder','BSQLJQ8','6024315859027',316,'vial','2026-07-27',198.95,'2026-05-17 12:21:54','2026-07-04 04:35:00',NULL),
(42,30,'ORS Powder','Cipla','Tablet','BT67BOP','0006912849348',0,'bottle','2028-05-31',1451.24,'2026-04-27 12:21:54','2026-07-04 04:35:00',NULL),
(43,8,'Domperidone 10','Mankind','Capsule','BFOQAM2','2651460405966',8,'box','2027-02-09',454.14,'2026-06-16 12:21:54','2026-07-04 04:35:00',NULL),
(44,28,'Amlodipine 5','Dr Reddy','Ointment','BPOXAE2','8113297462313',323,'strip','2028-03-17',852.14,'2026-04-29 12:21:54','2026-07-04 04:35:00',NULL),
(45,31,'Insulin Glargine','Zydus','Syrup','BO0PDY5','4548566872939',66,'box','2026-03-17',125.20,'2026-03-30 12:21:54','2026-07-04 04:35:00',NULL),
(46,11,'Pantoprazole 40','Lupin','Powder','BTYUI16','4408230327304',344,'bottle','2026-07-05',1175.76,'2026-03-22 12:21:54','2026-07-04 04:35:00',NULL),
(47,37,'B-Complex','Abbott','Drops','B2PJHL5','7994512883615',295,'pack','2028-12-16',1470.37,'2026-05-12 12:21:54','2026-07-04 04:35:00',NULL),
(48,1,'Betadine Ointment','Zydus','Tablet','B1MQ0QM','4370423677933',0,'strip','2028-02-17',753.72,'2026-02-20 12:21:54','2026-07-04 04:35:00',NULL),
(49,15,'Betadine Ointment','Sun Pharma','Capsule','BLGD7EX','6433667083149',3,'strip','2027-07-30',507.23,'2026-02-03 12:21:54','2026-07-04 04:35:00',NULL),
(50,26,'Pantoprazole 40','GSK','Inhaler','BRNQOXM','0931725097122',295,'box','2026-04-07',852.03,'2026-01-12 12:21:54','2026-07-04 04:35:00',NULL),
(51,8,'Ibuprofen 400','Cipla','Syrup','B6YCWZN','7831809914983',378,'strip','2026-08-02',954.44,'2026-05-11 12:21:54','2026-07-04 04:35:00',NULL),
(52,8,'Diclofenac Gel','Zydus','Inhaler','B2IQB0G','4792130964340',351,'bottle','2027-01-23',345.90,'2026-03-13 12:21:54','2026-07-04 04:35:00',NULL),
(53,30,'Amoxicillin 250','Abbott','Injection','BMQ8OZM','7087797361012',41,'tube','2026-10-19',487.28,'2026-05-25 12:21:54','2026-07-04 04:35:00',NULL),
(54,37,'Insulin Glargine','Lupin','Inhaler','BDLTE1M','7863371874846',0,'box','2027-09-14',1297.35,'2026-05-24 12:21:54','2026-07-04 04:35:00',NULL),
(55,37,'Amoxicillin 250','Alkem','Injection','BA0W07N','7755639257143',5,'pack','2026-03-12',206.14,'2026-04-07 12:21:54','2026-07-04 04:35:00',NULL),
(56,25,'Insulin Glargine','Alkem','Powder','BBYOXME','5194227242055',396,'vial','2026-07-18',1173.99,'2026-02-18 12:21:54','2026-07-04 04:35:00',NULL),
(57,24,'B-Complex','Pfizer','Inhaler','BNHJ6Z5','3980860734253',118,'tube','2026-12-10',1024.90,'2026-05-09 12:21:54','2026-07-04 04:35:00',NULL),
(58,22,'Ibuprofen 400','Lupin','Injection','BOWBQSW','9678337255199',48,'box','2028-03-29',1407.19,'2026-05-12 12:21:54','2026-07-04 04:35:00',NULL),
(59,27,'Eye Drops Lubricant','GSK','Capsule','BBEBWK9','3514929054442',111,'box','2028-11-14',1254.96,'2026-03-30 12:21:54','2026-07-04 04:35:00',NULL),
(60,12,'Cetirizine 10','Zydus','Capsule','BRQ3HTF','7507035299018',0,'box','2026-05-23',529.18,'2026-02-10 12:21:54','2026-07-04 04:35:00',NULL),
(61,36,'Betadine Ointment','Alkem','Powder','BDKGJMD','6485454566243',6,'strip','2026-07-30',748.09,'2026-04-21 12:21:54','2026-07-04 04:35:00',NULL),
(62,26,'Paracetamol 500','Lupin','Injection','BBXE9RV','8732458228898',146,'box','2028-07-23',622.96,'2026-03-11 12:21:54','2026-07-04 04:35:00',NULL),
(63,23,'Salbutamol Inhaler','Mankind','Capsule','BERS6SA','1424395089843',253,'vial','2026-09-08',1208.16,'2026-01-11 12:21:54','2026-07-04 04:35:00',NULL),
(64,5,'Atorvastatin 10','Zydus','Ointment','BWSJRDC','1483601608025',233,'tube','2027-08-23',404.56,'2026-01-20 12:21:54','2026-07-04 04:35:00',NULL),
(65,2,'Metformin 500','Sun Pharma','Capsule','BUDXDBV','8070200092848',245,'box','2026-05-15',401.92,'2026-03-03 12:21:54','2026-07-04 04:35:00',NULL),
(66,40,'Azithromycin 500','Sun Pharma','Powder','BJDJS0D','7131604919535',0,'bottle','2026-07-07',947.83,'2026-03-03 12:21:54','2026-07-04 04:35:00',NULL),
(67,14,'Paracetamol 500','Pfizer','Ointment','BEL1XR3','4441666788820',2,'box','2027-11-13',1477.98,'2026-04-29 12:21:54','2026-07-04 04:35:00',NULL),
(68,8,'Diclofenac Gel','GSK','Capsule','BQWUMSK','2107484153555',211,'bottle','2027-09-17',879.67,'2026-02-14 12:21:54','2026-07-04 04:35:00',NULL),
(69,39,'Insulin Glargine','Mankind','Ointment','BNBPVPR','3929765884274',216,'box','2028-09-15',510.79,'2026-02-11 12:21:54','2026-07-04 04:35:00',NULL),
(70,15,'Omeprazole 20','Abbott','Capsule','B03AASA','5025957431115',224,'strip','2026-05-12',1340.47,'2026-03-11 12:21:54','2026-07-04 04:35:00',NULL),
(71,26,'Insulin Glargine','Pfizer','Inhaler','B6MU09G','7284561358951',136,'pack','2026-08-01',1436.99,'2026-02-09 12:21:54','2026-07-04 04:35:00',NULL),
(72,15,'Eye Drops Lubricant','Cipla','Tablet','BOBMUGN','2496127559275',0,'strip','2027-12-15',813.09,'2026-06-13 12:21:54','2026-07-04 04:35:00',NULL),
(73,14,'Paracetamol 500','Sun Pharma','Capsule','BVOYQPL','3564978294252',5,'pack','2026-09-24',406.01,'2026-06-02 12:21:54','2026-07-04 04:35:00',NULL),
(74,32,'Metformin 500','Abbott','Drops','BVP7552','5713088803917',93,'pack','2027-02-15',120.78,'2026-03-28 12:21:54','2026-07-04 04:35:00',NULL),
(75,37,'B-Complex','GSK','Drops','BCOINXG','6579161926831',391,'tube','2026-03-19',422.42,'2026-06-02 12:21:54','2026-07-04 04:35:00',NULL),
(76,19,'Amlodipine 5','Cipla','Powder','BYVARIQ','9031865010720',113,'tube','2026-07-08',853.28,'2026-05-15 12:21:54','2026-07-04 04:35:00',NULL),
(77,36,'Atorvastatin 10','Alkem','Tablet','BL5R5YU','9296463749926',75,'box','2028-12-17',462.59,'2026-02-02 12:21:54','2026-07-04 04:35:00',NULL),
(78,3,'Amlodipine 5','Alkem','Inhaler','BKR9FMH','7226841776901',0,'pack','2027-04-13',290.16,'2026-04-23 12:21:54','2026-07-04 04:35:00',NULL),
(79,22,'Diclofenac Gel','Lupin','Tablet','B5RS28O','3136731992806',2,'pack','2028-11-20',1418.48,'2026-04-12 12:21:54','2026-07-04 04:35:00',NULL),
(80,13,'Ibuprofen 400','Dr Reddy','Injection','BSP69KM','4925435440190',204,'pack','2026-05-11',529.22,'2026-06-14 12:21:54','2026-07-04 04:35:00',NULL),
(81,14,'Amlodipine 5','Pfizer','Powder','BP2QB0C','8457284781040',134,'bottle','2026-07-23',1172.53,'2026-06-04 12:21:54','2026-07-04 04:35:00',NULL),
(82,5,'Ibuprofen 400','Mankind','Inhaler','BZ4BAUW','2047277597046',227,'bottle','2027-07-21',884.77,'2026-04-01 12:21:54','2026-07-04 04:35:00',NULL),
(83,29,'Atorvastatin 10','Lupin','Tablet','BZ7V0MK','3143041820538',277,'pack','2026-09-06',756.27,'2026-06-17 12:21:54','2026-07-04 04:35:00',NULL),
(84,23,'Ibuprofen 400','Sun Pharma','Drops','B0OKGR7','5378121105634',0,'pack','2028-10-03',1233.58,'2026-01-21 12:21:54','2026-07-04 04:35:00',NULL),
(85,30,'Paracetamol 500','Mankind','Syrup','BDTD00Y','8185168063417',7,'vial','2026-06-11',1055.19,'2026-05-17 12:21:54','2026-07-04 04:35:00',NULL),
(86,16,'Cetirizine 10','Abbott','Syrup','BHEQ9V6','7396738256127',78,'pack','2026-07-23',632.61,'2026-03-16 12:21:54','2026-07-04 04:35:00',NULL),
(87,22,'B-Complex','Mankind','Inhaler','B9APGAM','6527759024209',358,'tube','2028-06-05',776.41,'2026-05-17 12:21:54','2026-07-04 04:35:00',NULL),
(88,22,'Amlodipine 5','Cipla','Injection','B3YUSCN','1711949197636',168,'tube','2028-05-24',418.36,'2026-04-04 12:21:54','2026-07-04 04:35:00',NULL),
(89,2,'Azithromycin 500','Pfizer','Drops','BTX37WT','9088934447642',301,'vial','2026-12-29',588.42,'2026-02-23 12:21:54','2026-07-04 04:35:00',NULL),
(90,14,'Salbutamol Inhaler','Sun Pharma','Drops','BXV1OYJ','5396584367222',0,'pack','2026-05-18',314.08,'2026-06-13 12:21:54','2026-07-04 04:35:00',NULL),
(91,19,'B-Complex','Sun Pharma','Tablet','BZ4PZGH','0497881672257',6,'box','2026-07-10',1266.15,'2026-04-20 12:21:54','2026-07-04 04:35:00',NULL),
(92,3,'Paracetamol 500','Cipla','Tablet','BMA6RJL','8141091325336',216,'tube','2028-04-02',346.75,'2026-02-23 12:21:54','2026-07-04 04:35:00',NULL),
(93,17,'Amoxicillin 250','Lupin','Inhaler','BXWM78Z','7024047535151',239,'strip','2027-07-11',83.38,'2026-04-26 12:21:54','2026-07-04 04:35:00',NULL),
(94,37,'Amoxicillin 250','GSK','Ointment','BOKTOSA','3856981073284',285,'pack','2026-10-03',1470.41,'2026-02-19 12:21:54','2026-07-04 04:35:00',NULL),
(95,30,'Domperidone 10','Pfizer','Injection','BEMK0HN','4596775195738',173,'vial','2026-06-26',934.23,'2026-03-17 12:21:54','2026-07-04 04:35:00',NULL),
(96,11,'Cetirizine 10','Lupin','Capsule','BIFGBXN','6154525247779',0,'bottle','2026-07-26',992.34,'2026-02-16 12:21:54','2026-07-04 04:35:00',NULL),
(97,24,'Azithromycin 500','GSK','Drops','BJ5LUPB','3895144747167',3,'tube','2027-10-24',795.71,'2026-06-29 12:21:54','2026-07-04 04:35:00',NULL),
(98,14,'Azithromycin 500','Pfizer','Inhaler','BKUTPDR','5392427848361',332,'bottle','2028-02-20',1060.49,'2026-02-01 12:21:54','2026-07-04 04:35:00',NULL),
(99,30,'Metformin 500','Zydus','Ointment','BJT6GLU','6424471569776',344,'tube','2026-11-10',596.26,'2026-06-06 12:21:54','2026-07-04 04:35:00',NULL),
(100,22,'Salbutamol Inhaler','Lupin','Inhaler','BGOJTG2','3819005294065',299,'box','2026-04-04',1068.92,'2026-05-24 12:21:54','2026-07-04 04:35:00',NULL),
(101,36,'Eye Drops Lubricant','Zydus','Tablet','BLI8FQQ','3433072004404',232,'strip','2026-07-25',418.49,'2026-03-05 12:21:54','2026-07-04 04:35:00',NULL),
(102,21,'ORS Powder','GSK','Injection','BZ5RUQA','5810637617886',0,'tube','2026-12-24',1310.22,'2026-03-05 12:21:54','2026-07-04 04:35:00',NULL),
(103,27,'B-Complex','Mankind','Drops','BCTUFYK','8606086288091',8,'bottle','2027-04-21',814.44,'2026-04-29 12:21:54','2026-07-04 04:35:00',NULL),
(104,40,'Eye Drops Lubricant','Lupin','Drops','BMUBDCG','6186025156435',387,'strip','2028-03-19',145.03,'2026-02-08 12:21:54','2026-07-04 04:35:00',NULL),
(105,11,'Azithromycin 500','Pfizer','Syrup','BKMCEXZ','5983778153046',393,'pack','2026-05-09',639.39,'2026-01-14 12:21:54','2026-07-04 04:35:00',NULL),
(106,11,'ORS Powder','Lupin','Tablet','BYJSQCR','0755099560408',110,'vial','2026-07-15',1181.71,'2026-05-04 12:21:54','2026-07-04 04:35:00',NULL),
(107,12,'Ibuprofen 400','Alkem','Syrup','B11BCGM','6138764040643',322,'bottle','2027-03-12',513.69,'2026-02-04 12:21:54','2026-07-04 04:35:00',NULL),
(108,29,'Omeprazole 20','Alkem','Inhaler','B3VHDGJ','6370783602154',0,'vial','2028-02-29',200.15,'2026-06-06 12:21:54','2026-07-04 04:35:00',NULL),
(109,9,'Amoxicillin 250','Alkem','Injection','BQ9HGDN','4202200490032',7,'strip','2026-11-20',196.84,'2026-05-16 12:21:54','2026-07-04 04:35:00',NULL),
(110,22,'Omeprazole 20','Cipla','Injection','BNWBUWG','0061520990363',110,'strip','2026-06-23',353.36,'2026-01-21 12:21:54','2026-07-04 04:35:00',NULL),
(111,29,'Vitamin D3','Dr Reddy','Injection','BZPBQP3','6906724570376',189,'vial','2026-07-19',1295.49,'2026-02-20 12:21:54','2026-07-04 04:35:00',NULL),
(112,19,'Amoxicillin 250','Pfizer','Injection','BOCVU4O','2479240413112',169,'pack','2027-04-22',908.13,'2026-01-07 12:21:54','2026-07-04 04:35:00',NULL),
(113,27,'Cetirizine 10','GSK','Tablet','B6TCFV9','5234127263924',197,'bottle','2028-02-28',176.13,'2026-02-28 12:21:54','2026-07-04 04:35:00',NULL),
(114,21,'Eye Drops Lubricant','Lupin','Syrup','B8JHMMM','5045767602987',0,'box','2027-10-06',442.69,'2026-03-26 12:21:54','2026-07-04 04:35:00',NULL),
(115,10,'Betadine Ointment','Zydus','Tablet','BVCE4R2','4890682973701',4,'bottle','2026-04-30',794.79,'2026-03-07 12:21:54','2026-07-04 04:35:00',NULL),
(116,13,'Cetirizine 10','Lupin','Inhaler','BF56VYA','1651389644799',105,'strip','2026-07-24',335.73,'2026-03-09 12:21:54','2026-07-04 04:35:00',NULL),
(117,16,'Domperidone 10','Abbott','Powder','BLPJDZR','8316080079273',82,'pack','2027-06-19',795.29,'2026-05-17 12:21:54','2026-07-04 04:35:00',NULL),
(118,40,'Insulin Glargine','Abbott','Tablet','B6BO0Q9','7542637310358',295,'bottle','2028-11-13',809.42,'2026-04-25 12:21:54','2026-07-04 04:35:00',NULL),
(119,30,'Cetirizine 10','Zydus','Powder','BOGG0PV','0662697360463',281,'box','2027-07-25',137.01,'2026-06-06 12:21:54','2026-07-04 04:35:00',NULL),
(120,26,'Vitamin D3','Cipla','Inhaler','BM4EXCE','7231419631612',0,'strip','2026-07-03',329.55,'2026-03-18 12:21:54','2026-07-04 04:35:00',NULL);
/*!40000 ALTER TABLE `medicines` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `migrations`
--

DROP TABLE IF EXISTS `migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `migrations` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `migration` varchar(255) NOT NULL,
  `batch` int(11) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=15 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `migrations`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `migrations` WRITE;
/*!40000 ALTER TABLE `migrations` DISABLE KEYS */;
INSERT INTO `migrations` VALUES
(1,'0001_01_01_000000_create_users_table',1),
(2,'0001_01_01_000001_create_cache_table',1),
(3,'0001_01_01_000002_create_jobs_table',1),
(4,'2026_07_04_000001_create_plans_table',1),
(5,'2026_07_04_000002_create_devices_table',1),
(6,'2026_07_04_000003_create_entitlements_table',1),
(7,'2026_07_04_000004_create_app_settings_table',1),
(8,'2026_07_04_000005_create_backups_table',1),
(9,'2026_07_04_000006_create_purchase_logs_table',1),
(10,'2026_07_04_000007_add_is_admin_to_users_table',1),
(11,'2026_07_04_000101_create_customers_table',1),
(12,'2026_07_04_000102_create_stores_table',1),
(13,'2026_07_04_000103_create_medicines_table',1),
(14,'2026_07_04_000104_add_soft_deletes_to_plans_table',1);
/*!40000 ALTER TABLE `migrations` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `password_reset_tokens`
--

DROP TABLE IF EXISTS `password_reset_tokens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `password_reset_tokens` (
  `email` varchar(255) NOT NULL,
  `token` varchar(255) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `password_reset_tokens`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `password_reset_tokens` WRITE;
/*!40000 ALTER TABLE `password_reset_tokens` DISABLE KEYS */;
/*!40000 ALTER TABLE `password_reset_tokens` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `plans`
--

DROP TABLE IF EXISTS `plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `plans` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `product_id` varchar(255) NOT NULL,
  `billing_period` varchar(255) NOT NULL,
  `price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `currency` varchar(8) NOT NULL DEFAULT 'INR',
  `badge` varchar(255) DEFAULT NULL,
  `is_best_value` tinyint(1) NOT NULL DEFAULT 0,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 0,
  `features` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`features`)),
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `plans_product_id_unique` (`product_id`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `plans`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `plans` WRITE;
/*!40000 ALTER TABLE `plans` DISABLE KEYS */;
INSERT INTO `plans` VALUES
(1,'Free Plan','free','free',0.00,'INR',NULL,0,1,0,'[\"Up to 7 medicines\",\"Basic expiry & low-stock alerts\",\"Local backup\"]','2026-07-04 04:34:59','2026-07-04 04:34:59',NULL),
(2,'Yearly Plan','premium_yearly','yearly',999.00,'INR','BEST VALUE',1,1,1,'[\"Track unlimited medicines\",\"Advanced expiry alerts\",\"Detailed reports & analytics\",\"Secure cloud backup & restore\",\"Export to CSV & PDF\",\"Priority support\"]','2026-07-04 04:34:59','2026-07-04 04:34:59',NULL),
(3,'Monthly Plan','premium_monthly','monthly',99.00,'INR',NULL,0,1,2,'[\"Track unlimited medicines\",\"Advanced expiry alerts\",\"Detailed reports & analytics\",\"Secure cloud backup & restore\",\"Export to CSV & PDF\",\"Priority support\"]','2026-07-04 04:34:59','2026-07-04 04:34:59',NULL),
(4,'Lifetime','premium_lifetime','lifetime',2499.00,'INR',NULL,0,1,3,'[\"Track unlimited medicines\",\"Advanced expiry alerts\",\"Detailed reports & analytics\",\"Secure cloud backup & restore\",\"Export to CSV & PDF\",\"Priority support\"]','2026-07-04 04:34:59','2026-07-04 04:34:59',NULL);
/*!40000 ALTER TABLE `plans` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `purchase_logs`
--

DROP TABLE IF EXISTS `purchase_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `purchase_logs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `device_id` varchar(255) NOT NULL,
  `product_id` varchar(255) DEFAULT NULL,
  `purchase_token` varchar(255) DEFAULT NULL,
  `event` varchar(255) DEFAULT NULL,
  `result` varchar(255) DEFAULT NULL,
  `payload` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`payload`)),
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `purchase_logs_device_id_index` (`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `purchase_logs`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `purchase_logs` WRITE;
/*!40000 ALTER TABLE `purchase_logs` DISABLE KEYS */;
/*!40000 ALTER TABLE `purchase_logs` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `sessions`
--

DROP TABLE IF EXISTS `sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `sessions` (
  `id` varchar(255) NOT NULL,
  `user_id` bigint(20) unsigned DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  `payload` longtext NOT NULL,
  `last_activity` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `sessions_user_id_index` (`user_id`),
  KEY `sessions_last_activity_index` (`last_activity`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `sessions`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `sessions` WRITE;
/*!40000 ALTER TABLE `sessions` DISABLE KEYS */;
INSERT INTO `sessions` VALUES
('0mFQcesnKPtpWPm3Ri3Ve1xjBwDuXSIZQoQ6xCEM',NULL,'127.0.0.1','curl/8.7.1','eyJfdG9rZW4iOiJEUmNpUlc5bVJ0TUw3b2RvMTVhU0IxRTg5ekNrMXZpQ0tqWVBtYmxOIiwiX3ByZXZpb3VzIjp7InVybCI6Imh0dHA6XC9cLzEyNy4wLjAuMTo4MDAwXC9hZG1pblwvbG9naW4iLCJyb3V0ZSI6ImZpbGFtZW50LmFkbWluLmF1dGgubG9naW4ifSwiX2ZsYXNoIjp7Im9sZCI6W10sIm5ldyI6W119fQ==',1783166820),
('1c2XLgEXGlz3E8K3kxBGHWqRXj0GpWCi0yMIgwD3',NULL,'127.0.0.1','curl/8.7.1','eyJfdG9rZW4iOiJXcmdCZEVPeFVEak9hdXZxUXY4b2RZOTRWMGlobzBFSVc0OU9HU1ZCIiwiX3ByZXZpb3VzIjp7InVybCI6Imh0dHA6XC9cLzEyNy4wLjAuMTo4MDAwXC9hZG1pblwvbG9naW4iLCJyb3V0ZSI6ImZpbGFtZW50LmFkbWluLmF1dGgubG9naW4ifSwiX2ZsYXNoIjp7Im9sZCI6W10sIm5ldyI6W119fQ==',1783163567),
('F6xvxK6XFsHirRC1UYnEQ3U8CF5jBCBqfMRoWAoG',NULL,'127.0.0.1','curl/8.7.1','eyJfdG9rZW4iOiJxQktBb3pZcXg3aXJRcFhlamxBWUtwWm9FeHhBR2lmQUc3bDA2YVNtIiwiX3ByZXZpb3VzIjp7InVybCI6Imh0dHA6XC9cLzEyNy4wLjAuMTo4MDAwXC9hZG1pblwvbG9naW4iLCJyb3V0ZSI6ImZpbGFtZW50LmFkbWluLmF1dGgubG9naW4ifSwiX2ZsYXNoIjp7Im9sZCI6W10sIm5ldyI6W119fQ==',1783167984),
('l6LGwHNEeWYfKcCMJI6LNP1ePQt27sEfr7uqyanA',1,'127.0.0.1','Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:152.0) Gecko/20100101 Firefox/152.0','eyJfdG9rZW4iOiJtRlhzYXlUSmdRaE1ldDQ4Rlk5YXEwM2dhdFlya1Y5c0xvZDQ4SGVKIiwiX2ZsYXNoIjp7Im9sZCI6W10sIm5ldyI6W119LCJfcHJldmlvdXMiOnsidXJsIjoiaHR0cDpcL1wvMTI3LjAuMC4xOjgwMDBcL2FkbWluIiwicm91dGUiOiJmaWxhbWVudC5hZG1pbi5wYWdlcy5kYXNoYm9hcmQifSwibG9naW5fd2ViXzU5YmEzNmFkZGMyYjJmOTQwMTU4MGYwMTRjN2Y1OGVhNGUzMDk4OWQiOjEsInBhc3N3b3JkX2hhc2hfd2ViIjoiNDZlOTg0Y2E4OTY1NmVlNzg1NzgyMTQ2MGMzNWRhYzBhYzg5ZTYxYjRkMjA2MWM4Y2VmZDE2MzUwMTk2NzFiYSIsInRhYmxlcyI6eyJlMmFjYWQzY2EyMzNmMmI4ZjQyNDM5MWNhZDllYTVmYl9jb2x1bW5zIjpbeyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6ImRldmljZV9pZCIsImxhYmVsIjoiRGV2aWNlIGlkIiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOnRydWUsImlzVG9nZ2xlYWJsZSI6ZmFsc2UsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6bnVsbH0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6InBsYW4ubmFtZSIsImxhYmVsIjoiUGxhbiIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjp0cnVlLCJpc1RvZ2dsZWFibGUiOmZhbHNlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOm51bGx9LHsidHlwZSI6ImNvbHVtbiIsIm5hbWUiOiJwcm9kdWN0X2lkIiwibGFiZWwiOiJQcm9kdWN0IGlkIiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOnRydWUsImlzVG9nZ2xlYWJsZSI6ZmFsc2UsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6bnVsbH0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6InN0YXR1cyIsImxhYmVsIjoiU3RhdHVzIiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOnRydWUsImlzVG9nZ2xlYWJsZSI6ZmFsc2UsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6bnVsbH0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6ImV4cGlyeV90aW1lIiwibGFiZWwiOiJFeHBpcnkgdGltZSIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjp0cnVlLCJpc1RvZ2dsZWFibGUiOmZhbHNlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOm51bGx9LHsidHlwZSI6ImNvbHVtbiIsIm5hbWUiOiJpc19wcmVtaXVtIiwibGFiZWwiOiJJcyBwcmVtaXVtIiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOnRydWUsImlzVG9nZ2xlYWJsZSI6ZmFsc2UsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6bnVsbH0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6ImNyZWF0ZWRfYXQiLCJsYWJlbCI6IkNyZWF0ZWQgYXQiLCJpc0hpZGRlbiI6ZmFsc2UsImlzVG9nZ2xlZCI6ZmFsc2UsImlzVG9nZ2xlYWJsZSI6dHJ1ZSwiaXNUb2dnbGVkSGlkZGVuQnlEZWZhdWx0Ijp0cnVlfSx7InR5cGUiOiJjb2x1bW4iLCJuYW1lIjoidXBkYXRlZF9hdCIsImxhYmVsIjoiVXBkYXRlZCBhdCIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjpmYWxzZSwiaXNUb2dnbGVhYmxlIjp0cnVlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOnRydWV9XSwiN2JjYzU0YTJlZGFjODE2NWY1YmY5YTE5ODZiYTViZWVfY29sdW1ucyI6W3sidHlwZSI6ImNvbHVtbiIsIm5hbWUiOiJkZXZpY2VfaWQiLCJsYWJlbCI6IkRldmljZSBpZCIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjp0cnVlLCJpc1RvZ2dsZWFibGUiOmZhbHNlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOm51bGx9LHsidHlwZSI6ImNvbHVtbiIsIm5hbWUiOiJwcm9kdWN0X2lkIiwibGFiZWwiOiJQcm9kdWN0IGlkIiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOnRydWUsImlzVG9nZ2xlYWJsZSI6ZmFsc2UsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6bnVsbH0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6ImV2ZW50IiwibGFiZWwiOiJFdmVudCIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjp0cnVlLCJpc1RvZ2dsZWFibGUiOmZhbHNlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOm51bGx9LHsidHlwZSI6ImNvbHVtbiIsIm5hbWUiOiJyZXN1bHQiLCJsYWJlbCI6IlJlc3VsdCIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjp0cnVlLCJpc1RvZ2dsZWFibGUiOmZhbHNlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOm51bGx9LHsidHlwZSI6ImNvbHVtbiIsIm5hbWUiOiJjcmVhdGVkX2F0IiwibGFiZWwiOiJDcmVhdGVkIGF0IiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOmZhbHNlLCJpc1RvZ2dsZWFibGUiOnRydWUsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6dHJ1ZX0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6InVwZGF0ZWRfYXQiLCJsYWJlbCI6IlVwZGF0ZWQgYXQiLCJpc0hpZGRlbiI6ZmFsc2UsImlzVG9nZ2xlZCI6ZmFsc2UsImlzVG9nZ2xlYWJsZSI6dHJ1ZSwiaXNUb2dnbGVkSGlkZGVuQnlEZWZhdWx0Ijp0cnVlfV0sImQ0MjJjOTUyNzE1MDFiZTEzNTJkOWNmZmI0YzczNzczX2NvbHVtbnMiOlt7InR5cGUiOiJjb2x1bW4iLCJuYW1lIjoibmFtZSIsImxhYmVsIjoiTmFtZSIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjp0cnVlLCJpc1RvZ2dsZWFibGUiOmZhbHNlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOm51bGx9LHsidHlwZSI6ImNvbHVtbiIsIm5hbWUiOiJlbWFpbCIsImxhYmVsIjoiRW1haWwgYWRkcmVzcyIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjp0cnVlLCJpc1RvZ2dsZWFibGUiOmZhbHNlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOm51bGx9LHsidHlwZSI6ImNvbHVtbiIsIm5hbWUiOiJwaG9uZSIsImxhYmVsIjoiUGhvbmUiLCJpc0hpZGRlbiI6ZmFsc2UsImlzVG9nZ2xlZCI6dHJ1ZSwiaXNUb2dnbGVhYmxlIjpmYWxzZSwiaXNUb2dnbGVkSGlkZGVuQnlEZWZhdWx0IjpudWxsfSx7InR5cGUiOiJjb2x1bW4iLCJuYW1lIjoiY2l0eSIsImxhYmVsIjoiQ2l0eSIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjp0cnVlLCJpc1RvZ2dsZWFibGUiOmZhbHNlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOm51bGx9LHsidHlwZSI6ImNvbHVtbiIsIm5hbWUiOiJzdGF0ZSIsImxhYmVsIjoiU3RhdGUiLCJpc0hpZGRlbiI6ZmFsc2UsImlzVG9nZ2xlZCI6dHJ1ZSwiaXNUb2dnbGVhYmxlIjpmYWxzZSwiaXNUb2dnbGVkSGlkZGVuQnlEZWZhdWx0IjpudWxsfSx7InR5cGUiOiJjb2x1bW4iLCJuYW1lIjoic3RhdHVzIiwibGFiZWwiOiJTdGF0dXMiLCJpc0hpZGRlbiI6ZmFsc2UsImlzVG9nZ2xlZCI6dHJ1ZSwiaXNUb2dnbGVhYmxlIjpmYWxzZSwiaXNUb2dnbGVkSGlkZGVuQnlEZWZhdWx0IjpudWxsfSx7InR5cGUiOiJjb2x1bW4iLCJuYW1lIjoicGxhbi5uYW1lIiwibGFiZWwiOiJQbGFuIiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOnRydWUsImlzVG9nZ2xlYWJsZSI6ZmFsc2UsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6bnVsbH0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6InN0b3Jlc19jb3VudCIsImxhYmVsIjoiU3RvcmVzIiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOnRydWUsImlzVG9nZ2xlYWJsZSI6ZmFsc2UsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6bnVsbH0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6ImRldmljZV9pZCIsImxhYmVsIjoiRGV2aWNlIGlkIiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOmZhbHNlLCJpc1RvZ2dsZWFibGUiOnRydWUsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6dHJ1ZX0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6ImNyZWF0ZWRfYXQiLCJsYWJlbCI6IkNyZWF0ZWQgYXQiLCJpc0hpZGRlbiI6ZmFsc2UsImlzVG9nZ2xlZCI6ZmFsc2UsImlzVG9nZ2xlYWJsZSI6dHJ1ZSwiaXNUb2dnbGVkSGlkZGVuQnlEZWZhdWx0Ijp0cnVlfSx7InR5cGUiOiJjb2x1bW4iLCJuYW1lIjoidXBkYXRlZF9hdCIsImxhYmVsIjoiVXBkYXRlZCBhdCIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjpmYWxzZSwiaXNUb2dnbGVhYmxlIjp0cnVlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOnRydWV9LHsidHlwZSI6ImNvbHVtbiIsIm5hbWUiOiJkZWxldGVkX2F0IiwibGFiZWwiOiJEZWxldGVkIGF0IiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOmZhbHNlLCJpc1RvZ2dsZWFibGUiOnRydWUsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6dHJ1ZX1dLCIyMzI3MThiYzAyODU2Njc3MGRhMmEyNTUwNjE1OGFhMl9jb2x1bW5zIjpbeyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6Im5hbWUiLCJsYWJlbCI6Ik5hbWUiLCJpc0hpZGRlbiI6ZmFsc2UsImlzVG9nZ2xlZCI6dHJ1ZSwiaXNUb2dnbGVhYmxlIjpmYWxzZSwiaXNUb2dnbGVkSGlkZGVuQnlEZWZhdWx0IjpudWxsfSx7InR5cGUiOiJjb2x1bW4iLCJuYW1lIjoiZW1haWwiLCJsYWJlbCI6IkVtYWlsIiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOnRydWUsImlzVG9nZ2xlYWJsZSI6ZmFsc2UsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6bnVsbH0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6ImNpdHkiLCJsYWJlbCI6IkNpdHkiLCJpc0hpZGRlbiI6ZmFsc2UsImlzVG9nZ2xlZCI6dHJ1ZSwiaXNUb2dnbGVhYmxlIjpmYWxzZSwiaXNUb2dnbGVkSGlkZGVuQnlEZWZhdWx0IjpudWxsfSx7InR5cGUiOiJjb2x1bW4iLCJuYW1lIjoic3RhdHVzIiwibGFiZWwiOiJTdGF0dXMiLCJpc0hpZGRlbiI6ZmFsc2UsImlzVG9nZ2xlZCI6dHJ1ZSwiaXNUb2dnbGVhYmxlIjpmYWxzZSwiaXNUb2dnbGVkSGlkZGVuQnlEZWZhdWx0IjpudWxsfSx7InR5cGUiOiJjb2x1bW4iLCJuYW1lIjoicGxhbi5uYW1lIiwibGFiZWwiOiJQbGFuIiwiaXNIaWRkZW4iOmZhbHNlLCJpc1RvZ2dsZWQiOnRydWUsImlzVG9nZ2xlYWJsZSI6ZmFsc2UsImlzVG9nZ2xlZEhpZGRlbkJ5RGVmYXVsdCI6bnVsbH0seyJ0eXBlIjoiY29sdW1uIiwibmFtZSI6ImNyZWF0ZWRfYXQiLCJsYWJlbCI6IkpvaW5lZCIsImlzSGlkZGVuIjpmYWxzZSwiaXNUb2dnbGVkIjp0cnVlLCJpc1RvZ2dsZWFibGUiOmZhbHNlLCJpc1RvZ2dsZWRIaWRkZW5CeURlZmF1bHQiOm51bGx9XX19',1783169335),
('NSEso0WocMRAsbpSsiuygXdDbupGAWGHJaIrw3Kv',NULL,'127.0.0.1','curl/8.7.1','eyJfdG9rZW4iOiJHQkpHdll1QlIzTERKWHJidWlrWU9vT1JHdTdsRWNXSTh0REt4bzhQIiwiX3ByZXZpb3VzIjp7InVybCI6Imh0dHA6XC9cLzEyNy4wLjAuMTo4MDAwXC9hZG1pblwvbG9naW4iLCJyb3V0ZSI6ImZpbGFtZW50LmFkbWluLmF1dGgubG9naW4ifSwiX2ZsYXNoIjp7Im9sZCI6W10sIm5ldyI6W119fQ==',1783163567),
('Qeqa7fAfbGVavnqNmTuxBuk2kLN76ZKB7V6IBh4f',NULL,'127.0.0.1','curl/8.7.1','eyJfdG9rZW4iOiI3eWxyY2h3U3hRN3lOdG9FZ01xaXd1bXA0R3JJeTFyOVRnNXBsaW90IiwiX3ByZXZpb3VzIjp7InVybCI6Imh0dHA6XC9cLzEyNy4wLjAuMTo4MDAwXC9hZG1pblwvbG9naW4iLCJyb3V0ZSI6ImZpbGFtZW50LmFkbWluLmF1dGgubG9naW4ifSwiX2ZsYXNoIjp7Im9sZCI6W10sIm5ldyI6W119fQ==',1783166820),
('QJOEIEqF9UCcmDfx7F7hLxcG20vQx7BtZZX2JiDV',NULL,'127.0.0.1','curl/8.7.1','eyJfdG9rZW4iOiJIWmhMMmpDNElxUzg2emJia2tUNzN0b3VWa3NoYVQ5dUVjNVhEUnVMIiwiX3ByZXZpb3VzIjp7InVybCI6Imh0dHA6XC9cLzEyNy4wLjAuMTo4MDAwXC9hZG1pblwvbG9naW4iLCJyb3V0ZSI6ImZpbGFtZW50LmFkbWluLmF1dGgubG9naW4ifSwiX2ZsYXNoIjp7Im9sZCI6W10sIm5ldyI6W119fQ==',1783166850),
('TmgSgupznA1H6W17k7bxMdFn5dADnaRh6fDyONQh',NULL,'127.0.0.1','curl/8.7.1','eyJfdG9rZW4iOiJMV244S1h6QW93dGtoUnNQd0llb3lLSWVDTlNabVlzQU5kellCUDlqIiwiX3ByZXZpb3VzIjp7InVybCI6Imh0dHA6XC9cLzEyNy4wLjAuMTo4MDAwXC9hZG1pblwvbG9naW4iLCJyb3V0ZSI6ImZpbGFtZW50LmFkbWluLmF1dGgubG9naW4ifSwiX2ZsYXNoIjp7Im9sZCI6W10sIm5ldyI6W119fQ==',1783170194),
('tzBF0wJPn1KlfQprDhT0dQUL42lqy46oRZsg3QcX',NULL,'127.0.0.1','curl/8.7.1','eyJfdG9rZW4iOiJzeUROZVBzMnRCVmhablRZbVJneXhqNk9aRlMzcUlmS1Z5WVRFSmJaIiwiX3ByZXZpb3VzIjp7InVybCI6Imh0dHA6XC9cLzEyNy4wLjAuMTo4MDAwXC9hZG1pblwvbG9naW4iLCJyb3V0ZSI6ImZpbGFtZW50LmFkbWluLmF1dGgubG9naW4ifSwiX2ZsYXNoIjp7Im9sZCI6W10sIm5ldyI6W119fQ==',1783168930),
('W3V7Rb80CFgDuyP5nFHSNo0XRkrGo8LsOVtSfD0n',NULL,'127.0.0.1','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Code/1.127.0 Chrome/148.0.7778.97 Electron/42.2.0 Safari/537.36','eyJfdG9rZW4iOiJUaTVFVUIxMW14YlBOaG1VeE5LbUl0WVdxNThycVBIUDhEVFN1NzNHIiwidXJsIjp7ImludGVuZGVkIjoiaHR0cDpcL1wvMTI3LjAuMC4xOjgwMDBcL2FkbWluIn0sIl9wcmV2aW91cyI6eyJ1cmwiOiJodHRwOlwvXC8xMjcuMC4wLjE6ODAwMFwvYWRtaW5cL2xvZ2luIiwicm91dGUiOiJmaWxhbWVudC5hZG1pbi5hdXRoLmxvZ2luIn0sIl9mbGFzaCI6eyJvbGQiOltdLCJuZXciOltdfX0=',1783167141);
/*!40000 ALTER TABLE `sessions` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `stores`
--

DROP TABLE IF EXISTS `stores`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `stores` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `customer_id` bigint(20) unsigned NOT NULL,
  `store_name` varchar(255) NOT NULL,
  `phone` varchar(255) DEFAULT NULL,
  `address` varchar(255) DEFAULT NULL,
  `city` varchar(255) DEFAULT NULL,
  `state` varchar(255) DEFAULT NULL,
  `pincode` varchar(255) DEFAULT NULL,
  `gstin` varchar(255) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `stores_customer_id_foreign` (`customer_id`),
  CONSTRAINT `stores_customer_id_foreign` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=41 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `stores`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `stores` WRITE;
/*!40000 ALTER TABLE `stores` DISABLE KEYS */;
INSERT INTO `stores` VALUES
(1,3,'City Medicos','8615685616','83, Rampersaud Street','Ahmedabad','Gujarat','407391',NULL,1,'2025-12-26 12:21:54','2026-07-04 04:35:00',NULL),
(2,5,'Metro Medicos','8757329654','55, Zachariah Street','Kolkata','West Bengal','290930',NULL,1,'2026-04-07 12:21:54','2026-07-04 04:35:00',NULL),
(3,2,'Care Medical','8658770049','81, Das Street','Patna','Bihar','585839','G9NCG4JAUWAIPCG',1,'2026-04-15 12:21:54','2026-07-04 04:35:00',NULL),
(4,29,'Star Pharmacy','8620347741','71, Shah Street','Mumbai','Maharashtra','379737',NULL,1,'2026-02-15 12:21:54','2026-07-04 04:35:00',NULL),
(5,26,'Sri Chemist','8337359218','40, Goswami Street','Bengaluru','Karnataka','384917',NULL,1,'2026-05-30 12:21:54','2026-07-04 04:35:00',NULL),
(6,30,'Star Medicos','8821212018','78, Doshi Street','Jaipur','Rajasthan','730110','XJBOLJE3THG36IT',1,'2026-01-09 12:21:54','2026-07-04 04:35:00',NULL),
(7,9,'Apollo Chemist','8837972602','79, Nayar Street','Hyderabad','Telangana','139751',NULL,0,'2026-02-05 12:21:54','2026-07-04 04:35:00',NULL),
(8,27,'Sri Pharmacy','8497131506','67, Sama Street','Kolkata','West Bengal','661414',NULL,1,'2026-06-28 12:21:54','2026-07-04 04:35:00',NULL),
(9,29,'City Chemist','8646642607','13, Goyal Street','Patna','Bihar','573334','JILUI6ILIHPGPVD',1,'2026-07-01 12:21:54','2026-07-04 04:35:00',NULL),
(10,30,'City Medicos','8100027880','30, Reddy Street','Bhubaneswar','Odisha','202873',NULL,1,'2025-12-10 12:21:54','2026-07-04 04:35:00',NULL),
(11,8,'Sri Drug House','8353925504','24, Mann Street','Jaipur','Rajasthan','367744',NULL,1,'2026-01-01 12:21:54','2026-07-04 04:35:00',NULL),
(12,18,'Care Medical','8157407941','69, Chawla Street','Chennai','Tamil Nadu','361918','JUM5AR2Z1BJOCTA',1,'2026-04-05 12:21:54','2026-07-04 04:35:00',NULL),
(13,10,'City Chemist','8270959906','36, Bedi Street','Kolkata','West Bengal','246990',NULL,1,'2026-03-15 12:21:54','2026-07-04 04:35:00',NULL),
(14,27,'Star Pharmacy','8271954333','55, Lata Street','Hyderabad','Telangana','376723',NULL,0,'2026-04-23 12:21:54','2026-07-04 04:35:00',NULL),
(15,24,'Star Drug House','8750179942','60, Ramnarine Street','Pune','Maharashtra','576516','GO5HK0AOOSKRNZA',1,'2026-06-03 12:21:54','2026-07-04 04:35:00',NULL),
(16,2,'New Chemist','8482627431','69, Khan Street','Delhi','Delhi','327998',NULL,1,'2026-02-05 12:21:54','2026-07-04 04:35:00',NULL),
(17,18,'City Drug House','8320263183','15, Sunder Street','Patna','Bihar','549910',NULL,1,'2026-06-13 12:21:54','2026-07-04 04:35:00',NULL),
(18,28,'Care Pharmacy','8969350781','20, Andra Street','Pune','Maharashtra','203380','EEFUC4QJN0U3T6D',1,'2026-04-16 12:21:54','2026-07-04 04:35:00',NULL),
(19,2,'Sri Drug House','8571577996','24, Dada Street','Bhubaneswar','Odisha','156707',NULL,1,'2026-03-05 12:21:54','2026-07-04 04:35:00',NULL),
(20,6,'Star Pharmacy','8729039761','72, Bhatia Street','Hyderabad','Telangana','689487',NULL,1,'2026-01-26 12:21:54','2026-07-04 04:35:00',NULL),
(21,18,'Star Chemist','8964364281','10, Khosla Street','Chennai','Tamil Nadu','234644','QPHOL7HG7ZXBJVF',0,'2026-06-21 12:21:54','2026-07-04 04:35:00',NULL),
(22,2,'Care Drug House','8891426401','46, Chaudry Street','Pune','Maharashtra','658000',NULL,1,'2026-06-27 12:21:54','2026-07-04 04:35:00',NULL),
(23,9,'Metro Chemist','8570501397','19, Suresh Street','Hyderabad','Telangana','199836',NULL,1,'2025-12-09 12:21:54','2026-07-04 04:35:00',NULL),
(24,7,'Star Drug House','8461450035','22, Guha Street','Kolkata','West Bengal','415611','FAEPLDPX2MEOJOF',1,'2026-01-10 12:21:54','2026-07-04 04:35:00',NULL),
(25,8,'Care Pharmacy','8845857036','63, Borah Street','Patna','Bihar','577662',NULL,1,'2026-05-20 12:21:54','2026-07-04 04:35:00',NULL),
(26,14,'New Chemist','8460696089','62, Lanka Street','Hyderabad','Telangana','770367',NULL,1,'2026-03-08 12:21:54','2026-07-04 04:35:00',NULL),
(27,21,'Health Drug House','8017959593','33, Uppal Street','Pune','Maharashtra','345722','JX52YA9OQCW8H6N',1,'2026-05-28 12:21:54','2026-07-04 04:35:00',NULL),
(28,21,'Sri Medical','8066254700','95, Sekhon Street','Jaipur','Rajasthan','126613',NULL,0,'2026-05-24 12:21:54','2026-07-04 04:35:00',NULL),
(29,4,'Care Medicos','8899606491','81, Parekh Street','Chennai','Tamil Nadu','205507',NULL,1,'2026-04-02 12:21:54','2026-07-04 04:35:00',NULL),
(30,28,'Apollo Drug House','8321761502','69, Ramakrishnan Street','Mumbai','Maharashtra','111036','DEVABAGSTIYQUFZ',1,'2026-02-18 12:21:54','2026-07-04 04:35:00',NULL),
(31,29,'Apollo Medical','8738200601','49, Vala Street','Bhubaneswar','Odisha','134788',NULL,1,'2025-12-28 12:21:54','2026-07-04 04:35:00',NULL),
(32,3,'Care Medical','8441677822','60, Puri Street','Bhubaneswar','Odisha','365212',NULL,1,'2026-03-10 12:21:54','2026-07-04 04:35:00',NULL),
(33,8,'Apollo Chemist','8946497723','64, Chahal Street','Lucknow','Uttar Pradesh','290740','AX1TZ6CVFJMAA1K',1,'2026-06-21 12:21:54','2026-07-04 04:35:00',NULL),
(34,20,'Care Drug House','8265079436','79, Kurian Street','Bengaluru','Karnataka','712702',NULL,1,'2026-02-15 12:21:54','2026-07-04 04:35:00',NULL),
(35,2,'Sri Drug House','8382550826','67, Wali Street','Patna','Bihar','419493',NULL,0,'2026-06-07 12:21:54','2026-07-04 04:35:00',NULL),
(36,19,'Health Pharmacy','8525222909','78, Bedi Street','Mumbai','Maharashtra','690279','HBRQP7SCUEZSWVI',1,'2026-02-17 12:21:54','2026-07-04 04:35:00',NULL),
(37,13,'Care Chemist','8493569046','34, Toor Street','Mumbai','Maharashtra','276531',NULL,1,'2025-12-30 12:21:54','2026-07-04 04:35:00',NULL),
(38,4,'Metro Medical','8360154281','38, Chacko Street','Bhubaneswar','Odisha','139029',NULL,1,'2026-03-26 12:21:54','2026-07-04 04:35:00',NULL),
(39,24,'Apollo Chemist','8952545068','94, Cheema Street','Chennai','Tamil Nadu','593477','FVGGSHK3PZGDDJS',1,'2026-02-02 12:21:54','2026-07-04 04:35:00',NULL),
(40,5,'Sri Drug House','8540175841','21, Dara Street','Delhi','Delhi','705730',NULL,1,'2026-05-26 12:21:54','2026-07-04 04:35:00',NULL);
/*!40000 ALTER TABLE `stores` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `email` varchar(255) NOT NULL,
  `is_admin` tinyint(1) NOT NULL DEFAULT 0,
  `email_verified_at` timestamp NULL DEFAULT NULL,
  `password` varchar(255) NOT NULL,
  `remember_token` varchar(100) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `users_email_unique` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
INSERT INTO `users` VALUES
(1,'Akash Sahay','akash.sahay1@gmail.com',1,'2026-07-04 04:34:59','$2y$12$iFxHuuPrFoYs96mZAF6ZDuEmNXguG5AKImB7Sk.THk90JjcDlwVRG','ntpiN2fO369K1MDDoNqHpfHLjhA4g1UrSxepQ9wbvFPwe74HhmGhTI35DRCJ','2026-07-04 04:34:59','2026-07-04 04:34:59');
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;

--
-- Dumping events for database 'med_stock'
--

--
-- Dumping routines for database 'med_stock'
--
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*M!100616 SET NOTE_VERBOSITY=@OLD_NOTE_VERBOSITY */;

-- Dump completed on 2026-07-04 18:39:16
