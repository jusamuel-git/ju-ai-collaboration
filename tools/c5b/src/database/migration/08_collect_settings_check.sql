-- ============================================================
-- 08_collect_settings 사전·사후 점검 (읽기 전용, 변경 없음)
-- 2026-11-02
-- ============================================================
SET NAMES utf8mb4;

-- 1) 08 적용 여부: 추가 컬럼·테이블·공통코드
SELECT 'ju_protocol_group 컬럼' AS ITEM, COUNT(*) AS CNT, 4 AS EXPECTED FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ju_protocol_group' AND COLUMN_NAME IN ('FRAME_RULE','CMD_GAP_MS','INIT_ROUTINE','INIT_DELAY_MS')
UNION ALL
SELECT 'ju_protocol 컬럼', COUNT(*), 4 FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ju_protocol' AND COLUMN_NAME IN ('PTL_ROLES','PTL_ACTION','EXPECT_RULE','IDEMPOTENT_YN')
UNION ALL
SELECT 'ju_data_channel_map', COUNT(*), 1 FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ju_data_channel_map'
UNION ALL
SELECT '공통코드 PROL', COUNT(*), 3 FROM ju_com_code WHERE GRP_CD = 'PROL'
UNION ALL
SELECT '공통코드 PACT', COUNT(*), 4 FROM ju_com_code WHERE GRP_CD = 'PACT'
UNION ALL
SELECT '되돌리기 백업 테이블', COUNT(*), 2 FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('ju_mig08_bak_protocol','ju_mig08_bak_packet');

-- 2) 정정 대상(GTEC 검증 7개) 현재 상태 (08 전: PTL_TYPE 원래 값)
SELECT p.PTL_CD, p.PTL_TYPE, p.USE_YN,
       (SELECT COUNT(*) FROM ju_protocol_packet k WHERE k.PTL_GRP_CD = p.PTL_GRP_CD AND k.PTL_CD = p.PTL_CD AND k.DIRECTION = 'RX' AND k.USE_YN = 'YENO0001') AS RX_PACKETS
  FROM ju_protocol p
 WHERE p.PTL_GRP_CD = 'GTEC' AND p.PTL_CD IN ('GTEC0000','GTEC0001','GTEC0002','GTEC0100','GTEC0300','GTEC0301','GTEC0400')
 ORDER BY p.PTL_CD;

-- 3) 채널 매핑 대상 태그·장치
SELECT t.DAT_GR_CD, t.DAT_CD, t.DAT_IDX, t.TAG_ID, t.USE_YN, g.DEV_CD
  FROM ju_data_tag t JOIN ju_data_group g ON g.DAT_GR_CD = t.DAT_GR_CD
 WHERE t.DAT_GR_CD = 'DG_GTEC01' ORDER BY t.DAT_IDX;
