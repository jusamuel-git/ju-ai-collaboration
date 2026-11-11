package com.asdp.juprovider.core.protocol.action;

import static com.asdp.juprovider.core.action.contract.FieldSpec.code;
import static com.asdp.juprovider.core.action.contract.FieldSpec.integer;
import static com.asdp.juprovider.core.action.contract.FieldSpec.listOf;
import static com.asdp.juprovider.core.action.contract.FieldSpec.string;

import java.util.ArrayList;
import java.util.List;

import com.asdp.juprovider.core.action.contract.ActionContract;
import com.asdp.juprovider.core.action.contract.FieldSpec;
import com.asdp.juprovider.core.action.contract.OutputKind;

/**
 * 프로토콜관리(M02010100) Action 계약 — 모두 contractVersion 1 (결정 AC3·AC4·AC8·AC11)
 * Designer는 이 계약(필드명·형·필수·출력 kind)에 Binding 한다.
 *
 * C5c: 수집 설정(그룹 frameRule·cmdGapMs·initRoutine·initDelayMs)과 프로토콜 역할(ptlRoles·ptlAction·expectRule·idempotentYn)을
 * 선택 입력·상세 출력에 추가했다. 필드 추가만이라 기존 v1 호출은 그대로 동작한다 (contractVersion 1 유지).
 */
public final class ProtocolContracts {

    public static final int VERSION = 1;

    private ProtocolContracts() {
    }

    // ----- 공통 필드 -----

    private static FieldSpec grpKey() {
        return string("ptlGrpCd", true, 20);
    }

    private static FieldSpec ptlKey() {
        return string("ptlCd", true, 20);
    }

    private static List<FieldSpec> groupOutput(boolean detail) {
        List<FieldSpec> f = new ArrayList<>(List.of(
                string("ptlGrpCd", true, 20),
                string("ptlGrpNm", false, 100),
                string("ptlGrpDesc", false, 500),
                integer("pollingIntval", true),
                integer("timeoutMs", true),
                integer("retryCnt", true),
                code("useYn", true, "YENO"),
                integer("sortOrd", true),
                integer("protocolCount", true)));
        if (detail) {
            f.add(string("ptlGrpNmKey", false, 200));
            f.add(string("ptlGrpDescKey", false, 200));
            f.addAll(groupCollectFields());
        }
        return f;
    }

    /** C5c 그룹 수집 설정 (FRAME_RULE JSON v1, 명령 간격, 초기화 루틴 PTL_CD 쉼표 목록, 초기화 대기) */
    private static List<FieldSpec> groupCollectFields() {
        return List.of(
                string("frameRule", false, 4000),
                integer("cmdGapMs", false),
                string("initRoutine", false, 500),
                integer("initDelayMs", false));
    }

    /** C5c 프로토콜 역할 (PROL 코드 쉼표 목록, PACT 코드, 응답 판정 JSON, 멱등 YENO) */
    private static List<FieldSpec> protocolCollectFields() {
        return List.of(
                string("ptlRoles", false, 50),
                code("ptlAction", false, "PACT"),
                string("expectRule", false, 500),
                code("idempotentYn", false, "YENO"));
    }

    private static List<FieldSpec> packetFields() {
        return List.of(
                integer("packetSeq", true),
                string("packetType", false, 30),
                string("direction", true, 10),
                string("packetExpr", false, 4000),
                string("responsePtlCd", false, 20),
                string("parseRule", false, 4000),
                integer("dataCount", false),
                string("dataType", false, 30),
                string("dataPosition", false, 100));
    }

    private static List<FieldSpec> protocolOutput(boolean detail) {
        List<FieldSpec> f = new ArrayList<>(List.of(
                string("ptlGrpCd", true, 20),
                string("ptlCd", true, 20),
                code("ptlType", true, "PROT"),
                string("ptlTypeNm", false, 100),
                integer("ptlLen", false),
                string("ptlNm", false, 100),
                string("ptlDesc", false, 500),
                code("useYn", true, "YENO")));
        if (detail) {
            f.add(string("ptlVal", false, 4000));
            f.add(string("ptlNmKey", false, 200));
            f.add(string("ptlDescKey", false, 200));
            f.addAll(protocolCollectFields());
            List<FieldSpec> packet = new ArrayList<>(packetFields());
            packet.add(code("useYn", true, "YENO"));
            f.add(listOf("packets", true, packet));
        } else {
            f.add(integer("packetCount", true));
        }
        return f;
    }

    private static List<FieldSpec> with(List<FieldSpec> base, List<FieldSpec> extra) {
        List<FieldSpec> f = new ArrayList<>(base);
        f.addAll(extra);
        return List.copyOf(f);
    }

    private static List<FieldSpec> groupKeyOutput() {
        return List.of(string("ptlGrpCd", true, 20));
    }

    private static List<FieldSpec> protocolKeyOutput() {
        return List.of(string("ptlGrpCd", true, 20), string("ptlCd", true, 20));
    }

    // ----- Group -----

    public static final ActionContract GRP_SEARCH = ActionContract.of(VERSION, OutputKind.LIST,
            List.of(string("keyword", false, 100), code("useYn", false, "YENO")),
            groupOutput(false));

    public static final ActionContract GRP_GET = ActionContract.of(VERSION, OutputKind.RECORD,
            List.of(grpKey()),
            groupOutput(true));

    /** ptlGrpCd는 16자 이하 (기본 프로토콜 {그룹}0000 이 PTL_CD 20자에 들어가야 함) */
    public static final ActionContract GRP_CREATE = ActionContract.of(VERSION, OutputKind.KEY,
            with(List.of(
                    string("ptlGrpCd", true, 16),
                    string("ptlGrpNm", true, 100),
                    string("ptlGrpDesc", false, 500),
                    integer("pollingIntval", false),
                    integer("timeoutMs", false),
                    integer("retryCnt", false),
                    integer("sortOrd", false)), groupCollectFields()),
            groupKeyOutput());

    public static final ActionContract GRP_UPDATE = ActionContract.of(VERSION, OutputKind.KEY,
            with(List.of(
                    grpKey(),
                    string("ptlGrpNm", false, 100),
                    string("ptlGrpDesc", false, 500),
                    integer("pollingIntval", false),
                    integer("timeoutMs", false),
                    integer("retryCnt", false),
                    integer("sortOrd", false),
                    code("useYn", false, "YENO")), groupCollectFields()),
            groupKeyOutput());

    public static final ActionContract GRP_DELETE = ActionContract.of(VERSION, OutputKind.KEY,
            List.of(grpKey()),
            groupKeyOutput());

    // ----- Protocol -----

    public static final ActionContract SEARCH = ActionContract.of(VERSION, OutputKind.LIST,
            List.of(grpKey(), string("keyword", false, 100), code("useYn", false, "YENO")),
            protocolOutput(false));

    public static final ActionContract GET = ActionContract.of(VERSION, OutputKind.RECORD,
            List.of(grpKey(), ptlKey()),
            protocolOutput(true));

    public static final ActionContract CREATE = ActionContract.of(VERSION, OutputKind.KEY,
            with(List.of(
                    grpKey(),
                    ptlKey(),
                    code("ptlType", true, "PROT"),
                    integer("ptlLen", false),
                    string("ptlVal", false, 4000),
                    string("ptlNm", true, 100),
                    string("ptlDesc", false, 500),
                    listOf("packets", false, packetFields())), protocolCollectFields()),
            protocolKeyOutput());

    public static final ActionContract UPDATE = ActionContract.of(VERSION, OutputKind.KEY,
            with(List.of(
                    grpKey(),
                    ptlKey(),
                    code("ptlType", false, "PROT"),
                    integer("ptlLen", false),
                    string("ptlVal", false, 4000),
                    string("ptlNm", false, 100),
                    string("ptlDesc", false, 500),
                    code("useYn", false, "YENO"),
                    listOf("packets", false, packetFields())), protocolCollectFields()),
            protocolKeyOutput());

    public static final ActionContract DELETE = ActionContract.of(VERSION, OutputKind.KEY,
            List.of(grpKey(), ptlKey()),
            protocolKeyOutput());
}
