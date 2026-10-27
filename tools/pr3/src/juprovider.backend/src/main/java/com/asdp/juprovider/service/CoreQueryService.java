package com.asdp.juprovider.service;

import com.asdp.juprovider.dao.CoreQueryDao;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Service
public class CoreQueryService {

    private final CoreQueryDao coreQueryDao;

    public CoreQueryService(CoreQueryDao coreQueryDao) {
        this.coreQueryDao = coreQueryDao;
    }

    public List<Map<String, Object>> languages() {
        return coreQueryDao.selectLanguages();
    }

    public List<Map<String, Object>> commonGroups(String langCd) {
        return coreQueryDao.selectCommonGroups(langCd);
    }

    public List<Map<String, Object>> commonCodes(String grpCd, String langCd) {
        return coreQueryDao.selectCommonCodes(grpCd, langCd);
    }

    public List<Map<String, Object>> menus(String langCd) {
        return coreQueryDao.selectMenus(langCd);
    }

    public List<Map<String, Object>> devices() {
        return coreQueryDao.selectDevices();
    }

    public List<Map<String, Object>> dataGroups() {
        return coreQueryDao.selectDataGroups();
    }

    public List<Map<String, Object>> dataTags(String datGrCd) {
        return coreQueryDao.selectDataTags(datGrCd);
    }

    public List<Map<String, Object>> experiments() {
        return coreQueryDao.selectExperiments();
    }

    public List<Map<String, Object>> experimentRuns(Long expId) {
        return coreQueryDao.selectExperimentRuns(expId);
    }

    public List<Map<String, Object>> runtimeData(String clientId) {
        return coreQueryDao.selectRuntimeData(clientId);
    }
}
