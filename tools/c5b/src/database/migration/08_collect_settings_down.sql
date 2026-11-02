-- ============================================================
-- 08_collect_settings.sql 되돌리기
-- 2026-11-02
-- 08 적용 전 상태로 돌린다: 정정한 PTL_TYPE·PARSE_RULE 복원, 08이 추가한 RX 패킷 삭제,
-- ju_data_channel_map·추가 컬럼·공통코드 PROL/PACT 제거, ju_schema_version '08' 기록 삭제(있을 때).
-- 여러 번 실행해도 결과가 같다 (08 미적용 DB에서 실행해도 변경 없음).
-- 주의: 08 적용 후 화면에서 입력한 수집 설정·채널 매핑도 함께 지워진다.
-- ============================================================
SET NAMES utf8mb4;

-- 0) 백업 테이블이 없으면(미적용·이미 되돌림) 빈 테이블로 만들어 아래 문장이 그대로 지나가게 한다
CREATE TABLE IF NOT EXISTS `ju_mig08_bak_protocol` (
  `PTL_GRP_CD` varchar(20) NOT NULL,
  `PTL_CD` varchar(20) NOT NULL,
  `PTL_TYPE` varchar(8) NOT NULL,
  PRIMARY KEY (`PTL_GRP_CD`,`PTL_CD`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `ju_mig08_bak_packet` (
  `PTL_GRP_CD` varchar(20) NOT NULL,
  `PTL_CD` varchar(20) NOT NULL,
  `PACKET_SEQ` int(11) NOT NULL,
  `ROW_STATE` varchar(10) NOT NULL,
  `PARSE_RULE` longtext DEFAULT NULL,
  PRIMARY KEY (`PTL_GRP_CD`,`PTL_CD`,`PACKET_SEQ`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- 1) 프로토콜 유형 복원
UPDATE ju_protocol p
  JOIN ju_mig08_bak_protocol b ON b.PTL_GRP_CD = p.PTL_GRP_CD AND b.PTL_CD = p.PTL_CD
   SET p.PTL_TYPE = b.PTL_TYPE;

-- 2) RX 패킷: 해석 규칙 복원, 08이 추가한 패킷 삭제
UPDATE ju_protocol_packet k
  JOIN ju_mig08_bak_packet b ON b.PTL_GRP_CD = k.PTL_GRP_CD AND b.PTL_CD = k.PTL_CD AND b.PACKET_SEQ = k.PACKET_SEQ AND b.ROW_STATE = 'UPDATED'
   SET k.PARSE_RULE = b.PARSE_RULE;

DELETE k FROM ju_protocol_packet k
  JOIN ju_mig08_bak_packet b ON b.PTL_GRP_CD = k.PTL_GRP_CD AND b.PTL_CD = k.PTL_CD AND b.PACKET_SEQ = k.PACKET_SEQ AND b.ROW_STATE = 'INSERTED';

-- 3) 채널 매핑 테이블
DROP TABLE IF EXISTS ju_data_channel_map;

-- 4) 추가 컬럼
ALTER TABLE ju_protocol
  DROP COLUMN IF EXISTS `PTL_ROLES`,
  DROP COLUMN IF EXISTS `PTL_ACTION`,
  DROP COLUMN IF EXISTS `EXPECT_RULE`,
  DROP COLUMN IF EXISTS `IDEMPOTENT_YN`;

ALTER TABLE ju_protocol_group
  DROP COLUMN IF EXISTS `FRAME_RULE`,
  DROP COLUMN IF EXISTS `CMD_GAP_MS`,
  DROP COLUMN IF EXISTS `INIT_ROUTINE`,
  DROP COLUMN IF EXISTS `INIT_DELAY_MS`;

-- 5) 공통코드 PROL/PACT (detail은 FK CASCADE로 함께 삭제)
DELETE FROM ju_multi_lang
 WHERE RES_KEY IN ('GROUP.PROL.NM','GROUP.PACT.NM')
    OR RES_KEY LIKE 'CODE.PROL.%' OR RES_KEY LIKE 'CODE.PACT.%';
DELETE FROM ju_com_code WHERE GRP_CD IN ('PROL','PACT');
DELETE FROM ju_com_group WHERE GRP_CD IN ('PROL','PACT');

-- 6) 스키마 버전 기록 (07 ju_schema_version이 있을 때만)
DELIMITER $$
BEGIN NOT ATOMIC
  IF EXISTS (SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ju_schema_version') THEN
    EXECUTE IMMEDIATE 'DELETE FROM ju_schema_version WHERE SCHEMA_VER = ''08''';
  END IF;
END$$
DELIMITER ;

-- 7) 백업 테이블
DROP TABLE IF EXISTS ju_mig08_bak_packet;
DROP TABLE IF EXISTS ju_mig08_bak_protocol;
