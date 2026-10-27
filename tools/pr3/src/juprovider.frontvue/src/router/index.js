import { createRouter, createWebHistory } from 'vue-router'

import DeviceManagement from '../views/device/DeviceManagement.vue'
import ProtocolManagement from '../views/device/ProtocolManagement.vue'
import LoginView from '../views/auth/LoginView.vue'
import PasswordChangeView from '../views/auth/PasswordChangeView.vue'
import ForbiddenView from '../views/auth/ForbiddenView.vue'
import { hasMenu, isLoggedIn, isPasswordChangeRequired, session } from '../auth/session'
import { loadMe } from '../api/authApi'

const routes = [
  {
    path: '/',
    redirect: '/console/device/manage'
  },
  {
    path: '/login',
    name: 'login',
    component: LoginView,
    meta: { public: true }
  },
  {
    path: '/password-change',
    name: 'password-change',
    component: PasswordChangeView,
    meta: { passwordChange: true }
  },
  {
    path: '/forbidden',
    name: 'forbidden',
    component: ForbiddenView
  },
  {
    path: '/console/device/manage',
    name: 'device-management',
    component: DeviceManagement,
    // ju_menu M02010000 (장치관리, MNU_ID 15) 권한이 있어야 한다
    meta: { menuCode: 'M02010000' }
  },
  {
    path: '/console/device/protocol',
    name: 'protocol-management',
    component: ProtocolManagement,
    // ju_menu M02010100 (프로토콜관리, MNU_URL 동일). 데이터는 모두 Action(MNU_CD)으로 호출
    meta: { menuCode: 'M02010100' }
  }
]

const router = createRouter({
  history: createWebHistory('/juprovider/'),
  routes
})

/*
 * 로그인 가드
 * - 로그인 전: /login 외에는 로그인 화면으로 (원래 주소는 redirect로 보존)
 * - 비밀번호 변경 필요: /password-change 외에는 변경 화면으로
 * - 새로고침 후에는 /auth/me로 사용자·권한 메뉴를 다시 받는다
 * - meta.menuCode가 권한 메뉴에 없으면 /forbidden
 */
router.beforeEach(async to => {
  if (to.meta.public) {
    return isLoggedIn() && to.name === 'login' && !isPasswordChangeRequired() ? '/' : true
  }

  if (!isLoggedIn()) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  if (!session.menusLoaded) {
    try {
      await loadMe()
    } catch {
      return { name: 'login', query: { redirect: to.fullPath } }
    }
  }

  if (isPasswordChangeRequired()) {
    return to.meta.passwordChange ? true : { name: 'password-change', query: { redirect: to.fullPath } }
  }

  if (to.meta.menuCode && !hasMenu(to.meta.menuCode)) {
    return { name: 'forbidden' }
  }

  return true
})

export default router
