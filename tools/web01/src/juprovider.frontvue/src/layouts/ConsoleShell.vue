<script setup>
/*
 * 관리 콘솔 레이아웃 (WEB-02). /console/** 는 로그인 + 비밀번호 변경 완료 후에만 들어온다 (router 가드).
 * 상단: 콘솔 메뉴(권한 메뉴 중 이 앱에 화면이 있는 것), 사용자, 로그아웃(→ 공개 홈 /).
 */
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { clearSession, session } from '../auth/session'

const router = useRouter()

// 이 앱에 화면(route meta.menuCode)이 있고, 권한 메뉴에 포함된 것만. 이름은 서버 메뉴명
const consoleMenus = computed(() => router.getRoutes()
  .filter(r => r.path.startsWith('/console/') && r.meta.menuCode)
  .map(r => ({ path: r.path, menu: session.menus.find(m => m.menuCode === r.meta.menuCode) }))
  .filter(x => x.menu)
  .sort((a, b) => (a.menu.sortOrder ?? 0) - (b.menu.sortOrder ?? 0)))

function logout() {
  clearSession()
  router.replace('/')
}
</script>

<template>
  <div class="console">
    <header class="console-bar">
      <router-link to="/" class="brand">JuProvider</router-link>
      <nav class="console-nav" data-test="console-nav">
        <router-link v-for="x in consoleMenus" :key="x.path" :to="x.path">{{ x.menu.menuName }}</router-link>
      </nav>
      <span class="user">{{ session.user?.userName }} ({{ session.user?.loginId }})</span>
      <button type="button" data-test="logout" @click="logout">로그아웃</button>
    </header>
    <router-view />
  </div>
</template>

<style scoped>
.console-bar { display: flex; align-items: center; gap: 16px; padding: 8px 16px; border-bottom: 1px solid #dde3ea; background: #fff; font-size: 14px; flex-wrap: wrap; }
.brand { font-weight: 700; color: #152238; }
.console-nav { display: flex; gap: 12px; margin-right: auto; flex-wrap: wrap; }
.console-nav a { color: #475467; padding: 4px 2px; }
.console-nav a.router-link-active { color: #245fae; font-weight: 600; border-bottom: 2px solid #245fae; }
.user { color: #475467; }
button { cursor: pointer; }
</style>
