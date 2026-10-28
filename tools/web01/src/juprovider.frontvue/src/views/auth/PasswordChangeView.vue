<template>
  <div class="auth-page">
    <form class="auth-box" @submit.prevent="submit">
      <h1>비밀번호 변경</h1>
      <p v-if="required" class="auth-note">처음 로그인했거나 초기 비밀번호를 쓰고 있습니다. 비밀번호를 바꿔야 계속 사용할 수 있습니다.</p>

      <label>
        현재 비밀번호
        <input v-model="currentPassword" type="password" autocomplete="current-password" required>
      </label>

      <label>
        새 비밀번호 (8자 이상)
        <input v-model="newPassword" type="password" autocomplete="new-password" minlength="8" required>
      </label>

      <label>
        새 비밀번호 확인
        <input v-model="confirmPassword" type="password" autocomplete="new-password" minlength="8" required>
      </label>

      <p v-if="message" class="auth-error">{{ message }}</p>

      <button type="submit" :disabled="loading">
        {{ loading ? '변경 중...' : '변경' }}
      </button>
    </form>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { changePassword, errorMessage, loadMe, login } from '../../api/authApi'
import { clearSession, isPasswordChangeRequired, session } from '../../auth/session'

const route = useRoute()
const router = useRouter()

const currentPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const message = ref('')
const loading = ref(false)

const required = computed(() => isPasswordChangeRequired())

async function submit() {
  message.value = ''

  if (newPassword.value !== confirmPassword.value) {
    message.value = '새 비밀번호가 서로 다릅니다.'
    return
  }

  loading.value = true

  try {
    const loginId = session.user?.loginId
    await changePassword(currentPassword.value, newPassword.value)

    // 변경 전 토큰은 서버에서 무효가 되므로 새 비밀번호로 다시 로그인한다.
    try {
      await login(loginId, newPassword.value)
    } catch {
      clearSession()
      await router.replace({ name: 'login' })
      return
    }
    await loadMe()

    const redirect = route.query.redirect
    await router.replace(
      typeof redirect === 'string' && redirect.startsWith('/') && !redirect.startsWith('//') ? redirect : '/console'
    )
  } catch (error) {
    message.value = errorMessage(error, '비밀번호를 바꾸지 못했습니다.')
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.auth-page { min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 16px; }
.auth-box { width: 100%; max-width: 360px; display: flex; flex-direction: column; gap: 12px; }
.auth-box h1 { margin: 0 0 8px; font-size: 22px; }
.auth-box label { display: flex; flex-direction: column; gap: 4px; font-size: 14px; }
.auth-box input { padding: 8px; font-size: 14px; }
.auth-box button { padding: 10px; font-size: 14px; cursor: pointer; }
.auth-note { margin: 0; font-size: 13px; }
.auth-error { color: #c0392b; margin: 0; font-size: 13px; }
</style>
