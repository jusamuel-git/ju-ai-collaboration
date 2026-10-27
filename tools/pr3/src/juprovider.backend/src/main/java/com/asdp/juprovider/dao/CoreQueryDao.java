package com.asdp.juprovider.dao;

import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Map;

public interface CoreQueryDao {

    List<Map<String, Object>> selectLanguages();

    List<Map<String, Object>> selectCommonGroups(
            @Param("langCd") String langCd);

    List<Map<String, Object>> selectCommonCodes(
            @Param("grpCd") String grpCd,
            @Param("langCd") String langCd);

    List<Map<String, Object>> selectMenus(
            @Param("langCd") String langCd);

    List<Map<String, Object>> selectDevices();

    List<Map<String, Object>> selectDataGroups();

    List<Map<String, Object>> selectDataTags(
            @Param("datGrCd") String datGrCd);

    List<Map<String, Object>> selectExperiments();

    List<Map<String, Object>> selectExperimentRuns(
            @Param("expId") Long expId);

    List<Map<String, Object>> selectRuntimeData(
            @Param("clientId") String clientId);
}
