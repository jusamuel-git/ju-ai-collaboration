import api from './api'

/**
 * JuProvider Dynamic Action API
 *
 * menuId     : 현재 메뉴의 MNU_ID
 * actionCode : SEARCH, GET, CREATE, UPDATE, DELETE ...
 * parameters : Action Handler에 전달할 파라미터
 * langCd     : 선택 언어 코드
 */
export async function executeAction(
  menuId,
  actionCode,
  parameters = {},
  langCd = 'LANG0001'
) {
  if (menuId == null) {
    throw new Error('menuId가 필요합니다.')
  }

  if (!actionCode) {
    throw new Error('actionCode가 필요합니다.')
  }

  const response = await api.post(
    `/action/${menuId}/${actionCode}`,
    {
      parameters
    },
    {
      params: {
        langCd
      }
    }
  )

  return response.data
}

/**
 * 메뉴코드 기반 Action 호출 (PR-3, Action Contract)
 *
 * POST /api/action/{MNU_CD}/{ACT_CD}  body { contractVersion, parameters }
 *
 * menuCode        : ju_menu.MNU_CD (예: M02010100)
 * actionCode      : GRP_SEARCH, SEARCH, GET, CREATE ...
 * parameters      : 입력 계약(Input Contract)에 선언된 필드만 보낸다 (그 외 UNKNOWN_FIELD)
 * contractVersion : 화면이 기대하는 계약 버전. 서버와 다르면 400 VALIDATION (errors[].code CONTRACT_VERSION_MISMATCH)
 *
 * 성공: ApiResponse { success, data, contractVersion }
 * 실패: axios 오류. error.response.data = { message, code, errors: [{ field, code, message }] }
 */
export async function executeByCode(
  menuCode,
  actionCode,
  parameters = {},
  { contractVersion, langCd = 'LANG0001' } = {}
) {
  if (!/^M\d{8}$/.test(menuCode || '')) {
    throw new Error('menuCode 형식이 올바르지 않습니다: ' + menuCode)
  }

  if (!actionCode) {
    throw new Error('actionCode가 필요합니다.')
  }

  const body = { parameters }

  if (contractVersion != null) {
    body.contractVersion = contractVersion
  }

  const response = await api.post(
    `/action/${menuCode}/${actionCode}`,
    body,
    { params: { langCd } }
  )

  return response.data
}

/** Action 오류 응답 → { message, code, fieldErrors: { field: message } } */
export function actionError(error, fallback = '요청을 처리하지 못했습니다.') {
  const data = error?.response?.data || {}
  const fieldErrors = {}

  for (const item of data.errors || []) {
    if (item?.field && !fieldErrors[item.field]) {
      fieldErrors[item.field] = item.message || item.code
    }
  }

  return {
    status: error?.response?.status || 0,
    code: data.code || '',
    message: data.message || error?.message || fallback,
    fieldErrors
  }
}

export const actionApi = {
  execute: executeAction,
  executeByCode
}

export default actionApi