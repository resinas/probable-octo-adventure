USE appdb;

CREATE TABLE `users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `avatar_path` varchar(255) DEFAULT NULL,
  `company` varchar(255) DEFAULT NULL,
  `country` varchar(255) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `firstname` varchar(255) DEFAULT NULL,
  `last_download_messages` datetime(6) DEFAULT NULL,
  `last_download_pictures` datetime(6) DEFAULT NULL,
  `lastname` varchar(255) DEFAULT NULL,
  `password` varchar(255) DEFAULT NULL,
  `role` enum('INACTIVE','USER','SUPERUSER','ADMIN') DEFAULT NULL,
  `sharingchoice` bit(1) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=206 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `session_header` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `end_time` datetime(6) DEFAULT NULL,
  `host` varchar(255) DEFAULT NULL,
  `location` varchar(255) DEFAULT NULL,
  `name` varchar(255) DEFAULT NULL,
  `start_time` datetime(6) DEFAULT NULL,
  `type` enum('KEYNOTE','FOOD','COFFEE','PRACTICAL','QnA','PANEL','ai4bpm','automate','vipra','bpmeetiot','prody','objects','plc','innov8bpm','nlp4bpm','dlt4bpm','fmbpm','MAIN','BPMFORUM','PROCESSTECHNOLOGYFORUM','RESPONSIBLEBPMFORUM','INDUSTRYFORUM','EDUCATORSFORUM','TUTORIAL','DEMO','DOCTORALCONSORTIUM','JOURNALFIRST') CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=92 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `gallery_images` (
  `id` int NOT NULL AUTO_INCREMENT,
  `like_count` int NOT NULL,
  `path` varchar(255) DEFAULT NULL,
  `upload_time` datetime(6) DEFAULT NULL,
  `owner` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `FKca2hrlj2pcneecr21txvf7qmr` (`owner`),
  CONSTRAINT `FKca2hrlj2pcneecr21txvf7qmr` FOREIGN KEY (`owner`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `image_likes` (
  `image_id` int NOT NULL,
  `user_id` int NOT NULL,
  KEY `FK5iy707c1bw92sdfniu28xvodu` (`user_id`),
  KEY `FKggxpkq8gysvqo1gymy87hp8e0` (`image_id`),
  CONSTRAINT `FK5iy707c1bw92sdfniu28xvodu` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`),
  CONSTRAINT `FKggxpkq8gysvqo1gymy87hp8e0` FOREIGN KEY (`image_id`) REFERENCES `gallery_images` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `messages` (
  `id` int NOT NULL AUTO_INCREMENT,
  `creation_time` datetime(6) DEFAULT NULL,
  `text` varchar(255) DEFAULT NULL,
  `title` varchar(255) DEFAULT NULL,
  `author` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `FK315ptrp3yo2go9euyyyey0u44` (`author`),
  CONSTRAINT `FK315ptrp3yo2go9euyyyey0u44` FOREIGN KEY (`author`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `pages` (
  `id` int NOT NULL AUTO_INCREMENT,
  `content` text,
  `layout_id` int DEFAULT NULL,
  `title` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `read_messages` (
  `user_id` int NOT NULL,
  `message_id` int NOT NULL,
  KEY `FKlo0kefqxbwut7kew9r80qxuud` (`message_id`),
  KEY `FKetu2i8us42euu42t0os6hnqlc` (`user_id`),
  CONSTRAINT `FKetu2i8us42euu42t0os6hnqlc` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`),
  CONSTRAINT `FKlo0kefqxbwut7kew9r80qxuud` FOREIGN KEY (`message_id`) REFERENCES `messages` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


CREATE TABLE `session_content` (
  `id` bigint NOT NULL,
  `content` text,
  PRIMARY KEY (`id`),
  CONSTRAINT `FKl0stkub2nma13ia0xf0s6g9tp` FOREIGN KEY (`id`) REFERENCES `session_header` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


CREATE TABLE `session_likes` (
  `sessionheader_id` int NOT NULL,
  `user_id` bigint NOT NULL,
  KEY `FK52lsti42sn2gmt878wbari1fp` (`user_id`),
  KEY `FKcf4gql3qfrncn15nr4lx2ogcq` (`sessionheader_id`),
  CONSTRAINT `FK52lsti42sn2gmt878wbari1fp` FOREIGN KEY (`user_id`) REFERENCES `session_header` (`id`),
  CONSTRAINT `FKcf4gql3qfrncn15nr4lx2ogcq` FOREIGN KEY (`sessionheader_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

