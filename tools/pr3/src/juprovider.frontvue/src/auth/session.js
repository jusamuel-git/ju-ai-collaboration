import { reactive } from 'vue'

/*
 * JU 로그인 세션 (JU-1C)
 * - Access Token은 sessionStorage에 둔다 (탭을 닫으면 삭제)
 * - 사용자·권한 메뉴는 로그인/새로고침 때 /auth/me로 다시 받는다
 * - 비밀번호 변경이 필요하면(passwordChangeRequired) 변경 화면만 쓸 수 있다
 */
const TOKEN_KEY = 'juprovider.accessToken'
const EXPIRES_KEY = 'juprovider.expiresAt'
const USER_KEY = 'juprovider.user'
const PWC_KEY = 'juprovider.passwordChangeRequired'

function readJson(key) {
  try {
    const value = sessionStorage.getItem(key)
    return value ? JSON.parse(value) : null
  } catch {
    return null
  }
}

export const session = reactive({
  user: readJson(USER_KEY),
  passwordChangeRequired: sessionStorage.getItem(PWC_KEY) === 'true',
  menus: [],
  menusLoaded: false
})

export function getToken() {
  const token = sessionStorage.getItem(TOKEN_KEY)
  const expiresAt = sessionStorage.getItem(EXPIRES_KEY)

  if (!token || !expiresAt) {
    return null
  }

  if (new Date(expiresAt).getTime() <= Date.now()) {
    clearSession()
    return null
  }

  return token
}

export function isLoggedIn() {
  return getToken() !== null
}

export function isPasswordChangeRequired() {
  return session.passwordChangeRequired === true
}

/** 메뉴 코드 권한 (로그인 사용자의 AUTH_ATTR에 포함된 메뉴) */
export function hasMenu(menuCode) {
  return session.menus.some(menu => menu.menuCode === menuCode)
}

/**
 * 메뉴 Action 권한 비트 (PR-3)
 * /auth/me menus[].permission = AUTH_ATTR 16진 2자리. 01 조회, 02 등록, 04 수정, 08 삭제, 10 실행, 20 기타
 * 화면 버튼 표시용이다. 실제 권한 검사는 서버가 Action마다 한다 (403).
 */
export const PERM = Object.freeze({ VIEW: 0x01, CREATE: 0x02, UPDATE: 0x04, DELETE: 0x08, EXECUTE: 0x10 })

export function menuPermission(menuCode) {
  const menu = session.menus.find(item => item.menuCode === menuCode)
  const bits = parseInt(menu?.permission || '0', 16)
  return Number.isNaN(bits) ? 0 : bits
}

export function canAction(menuCode, bit) {
  return (menuPermission(menuCode) & bit) === bit
}

/** 로그인 응답 { accessToken, expiresAt, user, passwordChangeRequired } 저장 */
export function saveLogin(loginResponse) {
  sessionStorage.setItem(TOKEN_KEY, loginResponse.accessToken)
  sessionStorage.setItem(EXPIRES_KEY, loginResponse.expiresAt)
  sessionStorage.setItem(USER_KEY, JSON.stringify(loginResponse.user))
  sessionStorage.setItem(PWC_KEY, String(loginResponse.passwordChangeRequired === true))
  session.user = loginResponse.user
  session.passwordChangeRequired = loginResponse.passwordChangeRequired === true
  session.menus = []
  session.menusLoaded = false
}

/** /auth/me 응답 { user, passwordChangeRequired, menus } 저장 */
export function saveMe(me) {
  session.user = me.user
  session.passwordChangeRequired = me.passwordChangeRequired === true
  session.menus = me.menus || []
  session.menusLoaded = true
  sessionStorage.setItem(USER_KEY, JSON.stringify(me.user))
  sessionStorage.setItem(PWC_KEY, String(session.passwordChangeRequired))
}

export function clearSession() {
  sessionStorage.removeItem(TOKEN_KEY)
  sessionStorage.removeItem(EXPIRES_KEY)
  sessionStorage.removeItem(USER_KEY)
  sessionStorage.removeItem(PWC_KEY)
  session.user = null
  session.passwordChangeRequired = false
  session.menus = []
  session.menusLoaded = false
}
