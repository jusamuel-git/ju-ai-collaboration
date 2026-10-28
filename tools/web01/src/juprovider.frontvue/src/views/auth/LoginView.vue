<template>
  <div class="auth-page">
    <form class="auth-box" @submit.prevent="submit">
      <h1>JuProvider</h1>

      <label>
        아이디
        <input v-model.trim="loginId" autocomplete="username" required>
      </label>

      <label>
        비밀번호
        <input v-model="password" type="password" autocomplete="current-password" required>
      </label>

      <p v-if="message" class="auth-error">{{ message }}</p>

      <button type="submit" :disabled="loading">
        {{ loading ? '로그인 중...' : '로그인' }}
      </button>
    </form>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { errorMessage, loadMe, login } from '../../api/authApi'

const route = useRoute()
const router = useRouter()

const loginId = ref('')
const password = ref('')
const message = ref('')
const loading = ref(false)

async function submit() {
  message.value = ''
  loading.value = true

  try {
    const result = await login(loginId.value, password.value)

    if (result.passwordChangeRequired) {
      await router.replace({ name: 'password-change', query: route.query })
      return
    }

    await loadMe()
    await router.replace(safeRedirect(route.query.redirect))
  } catch (error) {
    message.value = errorMessage(error, '로그인하지 못했습니다.')
  } finally {
    loading.value = false
  }
}

function safeRedirect(redirect) {
  return typeof redirect === 'string' && redirect.startsWith('/') && !redirect.startsWith('//')
    ? redirect
    : '/console'
}
</script>

<style scoped>
.auth-page { min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 16px; }
.auth-box { width: 100%; max-width: 360px; display: flex; flex-direction: column; gap: 12px; }
.auth-box h1 { margin: 0 0 8px; font-size: 22px; }
.auth-box label { display: flex; flex-direction: column; gap: 4px; font-size: 14px; }
.auth-box input { padding: 8px; font-size: 14px; }
.auth-box button { padding: 10px; font-size: 14px; cursor: pointer; }
.auth-error { color: #c0392b; margin: 0; font-size: 13px; }
</style>
