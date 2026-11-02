-- ============================================================
-- C5b 수집 설정 · 프로토콜 역할 · 채널 매핑
-- 2026-11-02 (C5 설계 C5-Q1~Q7, C5b 승인)
-- 06_protocol_actions.sql 다음에 실행한다 (07_schema_version.sql이 있으면 07 다음). 여러 번 실행해도 결과가 같다.
-- 되돌리기: 08_collect_settings_down.sql (변경 전 값은 ju_mig08_bak_* 에 보관)
-- 기존 데이터: 값이 아직 없는 행(새 컬럼 NULL)만 정정한다. 이미 설정된 값·논리삭제(USE_YN=YENO0002) 행은 바꾸지 않는다.
-- ============================================================
SET NAMES utf8mb4;

-- 0) 사전 확인: 기준 테이블과 프로토콜 유형 코드(PROT, 04)가 있어야 한다
DELIMITER $$
BEGIN NOT ATOMIC
  IF (SELECT COUNT(*) FROM information_schema.TABLES
       WHERE TABLE_SCHEMA = DATABASE()
         AND TABLE_NAME IN ('ju_protocol_group','ju_protocol','ju_protocol_packet','ju_device','ju_data_group','ju_data_tag','ju_com_group','ju_com_code','ju_multi_lang')) <> 9 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '08: 기준 테이블 없음 (baseline 확인)';
  END IF;
  IF (SELECT COUNT(*) FROM ju_com_code WHERE GRP_CD = 'PROT' AND COM_CD IN ('PROT0000','PROT0001','PROT0002','PROT0003')) <> 4 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '08: 프로토콜 유형 코드 PROT0000~0003 없음 (04 먼저)';
  END IF;
END$$
DELIMITER ;

-- 1) 프로토콜 그룹 수집 설정
ALTER TABLE ju_protocol_group
  ADD COLUMN IF NOT EXISTS `FRAME_RULE` longtext DEFAULT NULL COMMENT 'Frame Rule JSON v1 (kind/start/end/maxLen). NULL=Desktop 기본값',
  ADD COLUMN IF NOT EXISTS `CMD_GAP_MS` int(11) NOT NULL DEFAULT 0 COMMENT '같은 Link 명령 간 최소 간격(ms)',
  ADD COLUMN IF NOT EXISTS `INIT_ROUTINE` varchar(500) DEFAULT NULL COMMENT '연결·재연결 초기화 PTL_CD 쉼표 목록(순서대로 실행)',
  ADD COLUMN IF NOT EXISTS `INIT_DELAY_MS` int(11) NOT NULL DEFAULT 500 COMMENT '연결 후 초기화 시작 대기(ms)';

-- 2) 프로토콜 역할·동작·응답 판정·멱등
ALTER TABLE ju_protocol
  ADD COLUMN IF NOT EXISTS `PTL_ROLES` varchar(50) DEFAULT NULL COMMENT '역할 공통코드(PROL) 쉼표 목록. NULL=미설정',
  ADD COLUMN IF NOT EXISTS `PTL_ACTION` varchar(8) DEFAULT NULL COMMENT '실험 동작 공통코드(PACT). NULL=동작 없음',
  ADD COLUMN IF NOT EXISTS `EXPECT_RULE` varchar(500) DEFAULT NULL COMMENT '응답 판정 JSON: {"startsWith":".."} 또는 {"regex":".."}',
  ADD COLUMN IF NOT EXISTS `IDEMPOTENT_YN` varchar(8) DEFAULT NULL COMMENT '재시도 허용(멱등) 명시값 YENO. NULL=기본 규칙';

-- 3) 공통코드 PROL(프로토콜 역할), PACT(프로토콜 실험 동작). 이미 있으면 그대로 둔다
INSERT IGNORE INTO ju_com_group (GRP_CD, USE_YN, SORT_ORD) VALUES
('PROL','YENO0001',209),
('PACT','YENO0001',210);
INSERT IGNORE INTO ju_com_group_detail (GRP_CD, GRP_NM, GRP_DESC, GRP_NM_KEY, GRP_DESC_KEY) VALUES
('PROL','프로토콜역할','프로토콜이 수집에서 맡는 역할. ju_protocol.PTL_ROLES (쉼표 목록)','GROUP.PROL.NM','GROUP.PROL.DESC'),
('PACT','프로토콜동작','실험 시작·일시정지·정지에 쓰는 명령 표시. ju_protocol.PTL_ACTION','GROUP.PACT.NM','GROUP.PACT.DESC');
INSERT IGNORE INTO ju_com_code (GRP_CD, COM_CD, COM_VAL, COM_ATTR, USE_YN, SORT_ORD) VALUES
('PROL','PROL0001','INFO',NULL,'YENO0001',1),
('PROL','PROL0002','CONTROL',NULL,'YENO0001',2),
('PROL','PROL0003','DATA',NULL,'YENO0001',3),
('PACT','PACT0000','NONE',NULL,'YENO0001',0),
('PACT','PACT0001','START',NULL,'YENO0001',1),
('PACT','PACT0002','PAUSE',NULL,'YENO0001',2),
('PACT','PACT0003','STOP',NULL,'YENO0001',3);
INSERT IGNORE INTO ju_com_code_detail (GRP_CD, COM_CD, COM_NM, COM_DESC, COM_NM_KEY, COM_DESC_KEY) VALUES
('PROL','PROL0001','정보','장치확인·센서정보 등 조회 응답','CODE.PROL.PROL0001.NM','CODE.PROL.PROL0001.DESC'),
('PROL','PROL0002','제어','모드 설정·시작·정지 등 장치 제어','CODE.PROL.PROL0002.NM','CODE.PROL.PROL0002.DESC'),
('PROL','PROL0003','데이터','측정 데이터 수신(해석 규칙 필수)','CODE.PROL.PROL0003.NM','CODE.PROL.PROL0003.DESC'),
('PACT','PACT0000','없음','실험 동작 없음','CODE.PACT.PACT0000.NM','CODE.PACT.PACT0000.DESC'),
('PACT','PACT0001','시작','실험 시작 명령','CODE.PACT.PACT0001.NM','CODE.PACT.PACT0001.DESC'),
('PACT','PACT0002','일시정지','실험 일시정지 명령','CODE.PACT.PACT0002.NM','CODE.PACT.PACT0002.DESC'),
('PACT','PACT0003','정지','실험 정지 명령','CODE.PACT.PACT0003.NM','CODE.PACT.PACT0003.DESC');

INSERT INTO ju_multi_lang (LANG_CD, RES_KEY, RES_VAL)
SELECT v.LANG_CD, v.RES_KEY, v.RES_VAL
  FROM (
        SELECT 'LANG0001' AS LANG_CD, 'GROUP.PROL.NM' AS RES_KEY, '프로토콜역할' AS RES_VAL
        UNION ALL SELECT 'LANG0001', 'GROUP.PACT.NM',          '프로토콜동작'
        UNION ALL SELECT 'LANG0001', 'CODE.PROL.PROL0001.NM',  '정보'
        UNION ALL SELECT 'LANG0001', 'CODE.PROL.PROL0002.NM',  '제어'
        UNION ALL SELECT 'LANG0001', 'CODE.PROL.PROL0003.NM',  '데이터'
        UNION ALL SELECT 'LANG0001', 'CODE.PACT.PACT0000.NM',  '없음'
        UNION ALL SELECT 'LANG0001', 'CODE.PACT.PACT0001.NM',  '시작'
        UNION ALL SELECT 'LANG0001', 'CODE.PACT.PACT0002.NM',  '일시정지'
        UNION ALL SELECT 'LANG0001', 'CODE.PACT.PACT0003.NM',  '정지'
        UNION ALL SELECT 'LANG0002', 'GROUP.PROL.NM',          'Protocol Role'
        UNION ALL SELECT 'LANG0002', 'GROUP.PACT.NM',          'Protocol Action'
        UNION ALL SELECT 'LANG0002', 'CODE.PROL.PROL0001.NM',  'Info'
        UNION ALL SELECT 'LANG0002', 'CODE.PROL.PROL0002.NM',  'Control'
        UNION ALL SELECT 'LANG0002', 'CODE.PROL.PROL0003.NM',  'Data'
        UNION ALL SELECT 'LANG0002', 'CODE.PACT.PACT0000.NM',  'None'
        UNION ALL SELECT 'LANG0002', 'CODE.PACT.PACT0001.NM',  'Start'
        UNION ALL SELECT 'LANG0002', 'CODE.PACT.PACT0002.NM',  'Pause'
        UNION ALL SELECT 'LANG0002', 'CODE.PACT.PACT0003.NM',  'Stop'
       ) v
 WHERE EXISTS (SELECT 1 FROM ju_language l WHERE l.LANG_CD = v.LANG_CD)
   AND NOT EXISTS (SELECT 1 FROM ju_multi_lang x WHERE x.LANG_CD = v.LANG_CD AND x.RES_KEY = v.RES_KEY);

-- 4) 채널 매핑 (해석 결과 채널 키 → 논리 Data). 행이 없는 장치는 Desktop이 TAG_ID=CH<n> 임시 변환을 계속 쓴다
--    CHANNEL_KEY는 대소문자·0 채움까지 그대로 비교한다 ("1" ≠ "01", "CH1" ≠ "ch1") → utf8mb4_bin
--    PTL_CD NULL(=모든 프로토콜)도 중복을 막도록 UK는 PTL_CD_KEY(NULL→'')로 건다
CREATE TABLE IF NOT EXISTS `ju_data_channel_map` (
  `MAP_ID` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '매핑 ID',
  `DEV_CD` varchar(20) NOT NULL COMMENT 'JuProvider 장치코드',
  `CHANNEL_KEY` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT '해석 결과 채널 키(위치 "1" 또는 이름 "CH1", 그대로 비교)',
  `PTL_CD` varchar(20) DEFAULT NULL COMMENT '이 프로토콜 수신에만 적용. NULL=모든 프로토콜',
  `PTL_CD_KEY` varchar(20) AS (IFNULL(`PTL_CD`, '')) PERSISTENT COMMENT 'UK용 PTL_CD (NULL→빈 문자열)',
  `DAT_GR_CD` varchar(20) NOT NULL COMMENT 'DAQ 데이터 그룹코드',
  `DAT_CD` varchar(20) NOT NULL COMMENT 'DAQ 데이터코드',
  `DAT_IDX` int(11) NOT NULL COMMENT '그룹 내 데이터 순번',
  `SCALE` double NOT NULL DEFAULT 1 COMMENT '환산 배율 (값 × SCALE + OFFSET_VAL)',
  `OFFSET_VAL` double NOT NULL DEFAULT 0 COMMENT '환산 오프셋',
  `USE_YN` varchar(8) NOT NULL DEFAULT 'YENO0001' COMMENT '사용여부 공통코드(YENO)',
  `SORT_ORD` int(11) NOT NULL DEFAULT 0 COMMENT '처리 순서',
  PRIMARY KEY (`MAP_ID`),
  UNIQUE KEY `UK_DCMAP` (`DEV_CD`,`CHANNEL_KEY`,`PTL_CD_KEY`,`DAT_GR_CD`,`DAT_CD`,`DAT_IDX`),
  KEY `FK_DCMAP_TAG` (`DAT_GR_CD`,`DAT_CD`,`DAT_IDX`),
  CONSTRAINT `FK_DCMAP_DEVICE` FOREIGN KEY (`DEV_CD`) REFERENCES `ju_device` (`DEV_CD`),
  CONSTRAINT `FK_DCMAP_TAG` FOREIGN KEY (`DAT_GR_CD`, `DAT_CD`, `DAT_IDX`) REFERENCES `ju_data_tag` (`DAT_GR_CD`, `DAT_CD`, `DAT_IDX`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='장치 채널 → 논리 Data 매핑';

-- 5) 되돌리기용 백업 (처음 정정할 때 값만 보관, 재실행해도 덮어쓰지 않음)
CREATE TABLE IF NOT EXISTS `ju_mig08_bak_protocol` (
  `PTL_GRP_CD` varchar(20) NOT NULL,
  `PTL_CD` varchar(20) NOT NULL,
  `PTL_TYPE` varchar(8) NOT NULL COMMENT '08 적용 전 PTL_TYPE',
  PRIMARY KEY (`PTL_GRP_CD`,`PTL_CD`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='08 되돌리기용: 정정 전 프로토콜 유형';

CREATE TABLE IF NOT EXISTS `ju_mig08_bak_packet` (
  `PTL_GRP_CD` varchar(20) NOT NULL,
  `PTL_CD` varchar(20) NOT NULL,
  `PACKET_SEQ` int(11) NOT NULL,
  `ROW_STATE` varchar(10) NOT NULL COMMENT 'UPDATED(PARSE_RULE 변경) / INSERTED(08이 추가한 RX 패킷)',
  `PARSE_RULE` longtext DEFAULT NULL COMMENT '08 적용 전 PARSE_RULE (UPDATED)',
  PRIMARY KEY (`PTL_GRP_CD`,`PTL_CD`,`PACKET_SEQ`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='08 되돌리기용: 정정 전 RX 패킷';

-- 6) GTEC 실장비 검증값 정정 (C5-Q4: 검증된 7개만. 사용 중이고 PTL_ROLES가 아직 없는 행만)
--    6-1) RX 패킷 해석 규칙 (GTEC0002 센서정보, GTEC0400 저속 데이터): 사용 중 RX 패킷 중 첫 번째를 정정, 없으면 추가
CREATE TEMPORARY TABLE IF NOT EXISTS mig08_rx (
  PTL_CD varchar(20) NOT NULL PRIMARY KEY, PARSE_RULE varchar(500) NOT NULL, DATA_COUNT int NOT NULL
);
DELETE FROM mig08_rx;
INSERT INTO mig08_rx VALUES
('GTEC0002','{"v":1,"kind":"INFO","trim":"{}","fields":["CH1","CH2","CH3","CH4"],"absent":"000"}',0),
('GTEC0400','{"v":1,"kind":"TEXT","trim":"{}","sep":"SPACE","count":3}',3);

INSERT IGNORE INTO ju_mig08_bak_packet (PTL_GRP_CD, PTL_CD, PACKET_SEQ, ROW_STATE, PARSE_RULE)
SELECT k.PTL_GRP_CD, k.PTL_CD, k.PACKET_SEQ, 'UPDATED', k.PARSE_RULE
  FROM ju_protocol_packet k
  JOIN ju_protocol p ON p.PTL_GRP_CD = k.PTL_GRP_CD AND p.PTL_CD = k.PTL_CD
  JOIN mig08_rx v ON v.PTL_CD = k.PTL_CD
 WHERE k.PTL_GRP_CD = 'GTEC' AND p.USE_YN = 'YENO0001' AND p.PTL_ROLES IS NULL
   AND k.DIRECTION = 'RX' AND k.USE_YN = 'YENO0001'
   AND k.PACKET_SEQ = (SELECT MIN(x.PACKET_SEQ) FROM ju_protocol_packet x
                        WHERE x.PTL_GRP_CD = k.PTL_GRP_CD AND x.PTL_CD = k.PTL_CD AND x.DIRECTION = 'RX' AND x.USE_YN = 'YENO0001');

INSERT IGNORE INTO ju_mig08_bak_packet (PTL_GRP_CD, PTL_CD, PACKET_SEQ, ROW_STATE, PARSE_RULE)
SELECT p.PTL_GRP_CD, p.PTL_CD,
       COALESCE((SELECT MAX(x.PACKET_SEQ) FROM ju_protocol_packet x WHERE x.PTL_GRP_CD = p.PTL_GRP_CD AND x.PTL_CD = p.PTL_CD), 0) + 1,
       'INSERTED', NULL
  FROM ju_protocol p
  JOIN mig08_rx v ON v.PTL_CD = p.PTL_CD
 WHERE p.PTL_GRP_CD = 'GTEC' AND p.USE_YN = 'YENO0001' AND p.PTL_ROLES IS NULL
   AND NOT EXISTS (SELECT 1 FROM ju_protocol_packet x
                    WHERE x.PTL_GRP_CD = p.PTL_GRP_CD AND x.PTL_CD = p.PTL_CD AND x.DIRECTION = 'RX' AND x.USE_YN = 'YENO0001');

UPDATE ju_protocol_packet k
  JOIN ju_mig08_bak_packet b ON b.PTL_GRP_CD = k.PTL_GRP_CD AND b.PTL_CD = k.PTL_CD AND b.PACKET_SEQ = k.PACKET_SEQ AND b.ROW_STATE = 'UPDATED'
  JOIN ju_protocol p ON p.PTL_GRP_CD = k.PTL_GRP_CD AND p.PTL_CD = k.PTL_CD
  JOIN mig08_rx v ON v.PTL_CD = k.PTL_CD
   SET k.PARSE_RULE = v.PARSE_RULE
 WHERE p.PTL_ROLES IS NULL;

INSERT INTO ju_protocol_packet (PTL_GRP_CD, PTL_CD, PACKET_SEQ, PACKET_TYPE, DIRECTION, PACKET_EXPR, RESPONSE_PTL_CD, PARSE_RULE, DATA_COUNT, DATA_TYPE, DATA_POSITION, USE_YN)
SELECT b.PTL_GRP_CD, b.PTL_CD, b.PACKET_SEQ, 'RX_PACKET', 'RX', NULL, NULL, v.PARSE_RULE, v.DATA_COUNT, NULL, NULL, 'YENO0001'
  FROM ju_mig08_bak_packet b
  JOIN mig08_rx v ON v.PTL_CD = b.PTL_CD
 WHERE b.ROW_STATE = 'INSERTED'
   AND NOT EXISTS (SELECT 1 FROM ju_protocol_packet x WHERE x.PTL_GRP_CD = b.PTL_GRP_CD AND x.PTL_CD = b.PTL_CD AND x.PACKET_SEQ = b.PACKET_SEQ);

DROP TEMPORARY TABLE IF EXISTS mig08_rx;

--    6-2) 프로토콜 유형·역할·동작·응답 판정·멱등 (PTL_TYPE: PROT0001 TX_ONLY, PROT0002 RX_STREAM, PROT0003 TX_RX)
--         멱등은 명령별 명시값 (STOP 자동 규칙 없음): GTEC0100 모드 설정·GTEC0301 정지 = Y, 나머지 = NULL(기본 규칙)
--         응답 판정 regex는 SQL·JSON 이스케이프가 필요 없도록 [{] [}] [0-9] 로 쓴다
CREATE TEMPORARY TABLE IF NOT EXISTS mig08_ptl (
  PTL_CD varchar(20) NOT NULL PRIMARY KEY, PTL_TYPE varchar(8) NOT NULL, PTL_ROLES varchar(50) NOT NULL,
  PTL_ACTION varchar(8) NULL, EXPECT_RULE varchar(500) NULL, IDEMPOTENT_YN varchar(8) NULL
);
DELETE FROM mig08_ptl;
INSERT INTO mig08_ptl VALUES
('GTEC0000','PROT0003','PROL0001',NULL,'{"startsWith":"{OK"}',NULL),
('GTEC0001','PROT0003','PROL0001',NULL,'{"regex":"^[{][A-Za-z]"}',NULL),
('GTEC0002','PROT0003','PROL0001',NULL,'{"regex":"^[{][0-9]{3},[0-9]{3},[0-9]{3},[0-9]{3}[}]$"}',NULL),
('GTEC0100','PROT0001','PROL0002',NULL,NULL,'YENO0001'),
('GTEC0300','PROT0001','PROL0002','PACT0001',NULL,NULL),
('GTEC0301','PROT0001','PROL0002','PACT0003',NULL,'YENO0001'),
('GTEC0400','PROT0002','PROL0003',NULL,NULL,NULL);

INSERT IGNORE INTO ju_mig08_bak_protocol (PTL_GRP_CD, PTL_CD, PTL_TYPE)
SELECT p.PTL_GRP_CD, p.PTL_CD, p.PTL_TYPE
  FROM ju_protocol p JOIN mig08_ptl v ON v.PTL_CD = p.PTL_CD
 WHERE p.PTL_GRP_CD = 'GTEC' AND p.USE_YN = 'YENO0001' AND p.PTL_ROLES IS NULL;

UPDATE ju_protocol p
  JOIN mig08_ptl v ON v.PTL_CD = p.PTL_CD
   SET p.PTL_TYPE = v.PTL_TYPE, p.PTL_ROLES = v.PTL_ROLES, p.PTL_ACTION = v.PTL_ACTION,
       p.EXPECT_RULE = v.EXPECT_RULE, p.IDEMPOTENT_YN = v.IDEMPOTENT_YN
 WHERE p.PTL_GRP_CD = 'GTEC' AND p.USE_YN = 'YENO0001' AND p.PTL_ROLES IS NULL;

DROP TEMPORARY TABLE IF EXISTS mig08_ptl;

--    6-3) GTEC 그룹: 시작 문자 { … 끝 [CR][LF], 명령 간격 200ms, 재연결 시 STOP 먼저 → 장치확인 → 센서정보 → 모드
UPDATE ju_protocol_group
   SET FRAME_RULE = '{"v":1,"kind":"DELIM","start":"{","end":"[CR][LF]","maxLen":512}',
       CMD_GAP_MS = 200,
       INIT_ROUTINE = 'GTEC0301,GTEC0001,GTEC0002,GTEC0100',
       INIT_DELAY_MS = 500
 WHERE PTL_GRP_CD = 'GTEC' AND USE_YN = 'YENO0001' AND FRAME_RULE IS NULL;

--    6-4) 채널 매핑: SDEV_GTEC01 채널 "1"~"4" → DG_GTEC01 / GTEC-DATA-01~04 (사용 중 태그만, 없을 때만)
INSERT INTO ju_data_channel_map (DEV_CD, CHANNEL_KEY, PTL_CD, DAT_GR_CD, DAT_CD, DAT_IDX, SCALE, OFFSET_VAL, USE_YN, SORT_ORD)
SELECT g.DEV_CD, v.CH, NULL, t.DAT_GR_CD, t.DAT_CD, t.DAT_IDX, 1, 0, 'YENO0001', v.ORD
  FROM (SELECT '1' AS CH, 'GTEC-DATA-01' AS CD, 1 AS IDX, 1 AS ORD
        UNION ALL SELECT '2', 'GTEC-DATA-02', 2, 2
        UNION ALL SELECT '3', 'GTEC-DATA-03', 3, 3
        UNION ALL SELECT '4', 'GTEC-DATA-04', 4, 4) v
  JOIN ju_data_tag t ON t.DAT_GR_CD = 'DG_GTEC01' AND t.DAT_CD = v.CD AND t.DAT_IDX = v.IDX AND t.USE_YN = 'YENO0001'
  JOIN ju_data_group g ON g.DAT_GR_CD = t.DAT_GR_CD AND g.DEV_CD = 'SDEV_GTEC01'
  JOIN ju_device d ON d.DEV_CD = g.DEV_CD
 WHERE NOT EXISTS (SELECT 1 FROM ju_data_channel_map m
                    WHERE m.DEV_CD = g.DEV_CD AND m.CHANNEL_KEY = v.CH AND m.PTL_CD IS NULL
                      AND m.DAT_GR_CD = t.DAT_GR_CD AND m.DAT_CD = t.DAT_CD AND m.DAT_IDX = t.DAT_IDX);

-- 7) 스키마 버전 기록 (07 ju_schema_version이 있을 때만)
DELIMITER $$
BEGIN NOT ATOMIC
  IF EXISTS (SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ju_schema_version') THEN
    EXECUTE IMMEDIATE 'INSERT IGNORE INTO ju_schema_version (SCHEMA_VER, SCRIPT_NM, APPLY_TYPE, APPLIED_BY) VALUES (''08'', ''08_collect_settings.sql'', ''APPLY'', CURRENT_USER())';
  END IF;
END$$
DELIMITER ;

-- 확인: GTEC 정정 결과와 정정하지 않은 GTEC 프로토콜
SELECT g.PTL_GRP_CD, g.CMD_GAP_MS, g.INIT_DELAY_MS, g.INIT_ROUTINE, g.FRAME_RULE FROM ju_protocol_group g WHERE g.PTL_GRP_CD = 'GTEC';
SELECT p.PTL_CD, p.PTL_TYPE, p.PTL_ROLES, p.PTL_ACTION, p.IDEMPOTENT_YN, p.EXPECT_RULE, p.USE_YN
  FROM ju_protocol p WHERE p.PTL_GRP_CD = 'GTEC' ORDER BY (p.PTL_ROLES IS NULL), p.PTL_CD;
SELECT m.DEV_CD, m.CHANNEL_KEY, m.PTL_CD, m.DAT_GR_CD, m.DAT_CD, m.DAT_IDX, m.USE_YN FROM ju_data_channel_map m ORDER BY m.DEV_CD, m.SORT_ORD;
