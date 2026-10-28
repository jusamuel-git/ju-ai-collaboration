<script setup>
/*
 * 공개 홈페이지 레이아웃 (WEB-02). 로그인 없이 볼 수 있다.
 * 로그인 상태면 "콘솔로 이동", 아니면 "로그인"을 보여준다.
 */
import { computed } from 'vue'
import { isLoggedIn, session } from '../auth/session'

const loggedIn = computed(() => isLoggedIn() && !!session.user)
</script>

<template>
  <div class="public">
    <header class="public-header">
      <div class="container bar">
        <router-link to="/" class="brand">JuProvider</router-link>
        <nav>
          <router-link v-if="loggedIn" class="btn primary" to="/console" data-test="go-console">콘솔로 이동</router-link>
          <router-link v-else class="btn primary" to="/login" data-test="go-login">로그인</router-link>
        </nav>
      </div>
    </header>
    <router-view />
    <footer class="public-footer">
      <div class="container">ASDP · JuProvider</div>
    </footer>
  </div>
</template>

<style scoped>
.public { min-height: 100vh; display: flex; flex-direction: column; }
.public-header { height: 64px; background: #fff; border-bottom: 1px solid #dde3ea; }
.bar { height: 100%; display: flex; align-items: center; justify-content: space-between; }
.brand { font-size: 20px; font-weight: 700; color: #152238; }
.public-footer { margin-top: auto; padding: 20px 0; color: #667085; font-size: 13px; border-top: 1px solid #dde3ea; background: #fff; }
</style>
