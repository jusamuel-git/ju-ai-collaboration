<script setup>
/*
 * 프로토콜관리 (M02010100) — PR-3 Protocol Reference 화면
 *
 * - 데이터는 모두 Action(MNU_CD + ACT_CD, contractVersion 1)으로만 호출한다.
 * - 화면은 Designer가 이후 저장할 단위(Grid / Form / Button / Dialog)로 나누고,
 *   각 단위의 열·필드는 아래 정의 배열(= 계약 필드 Binding)로 그린다.
 * - 버튼 표시는 /auth/me 권한 비트(01 조회, 02 등록, 04 수정, 08 삭제). 실제 검사는 서버(403).
 * - 필드 오류(errors[].field)는 해당 입력 옆에, 패킷 오류(packets[i].필드)는 해당 칸에 표시한다.
 */
import { computed, onMounted, reactive, ref } from 'vue'
import api from '../../api/api'
import { actionError, executeByCode } from '../../api/actionApi'
import { PERM, canAction } from '../../auth/session'

const MENU = 'M02010100'
const CONTRACT = 1
const YES = 'YENO0001'
const ALL = 'YENO0000'

const perm = computed(() => ({
  create: canAction(MENU, PERM.CREATE),
  update: canAction(MENU, PERM.UPDATE),
  remove: canAction(MENU, PERM.DELETE)
}))

function call(actCd, parameters) {
  return executeByCode(MENU, actCd, parameters, { contractVersion: CONTRACT })
}

/* 빈 값은 보내지 않는다 (선택 항목 미입력 = 미지정/유지). 숫자 필드는 정수로 바꾼다. */
function compact(source, fields, numberFields = []) {
  const out = {}
  for (const f of fields) {
    const v = source[f]
    if (v === undefined || v === null || v === '') continue
    out[f] = numberFields.includes(f) && /^-?\d+$/.test(String(v)) ? Number(v) : v
  }
  return out
}

/* ---------- 공통코드 (PROT, YENO) ---------- */
const codes = reactive({ PROT: [], YENO: [] })

async function loadCode(grpCd) {
  try {
    const r = await api.get(`/core/system-codes/${grpCd}`, { params: { langCd: 'LANG0001' } })
    codes[grpCd] = Array.isArray(r.data) ? r.data : []
  } catch {
    codes[grpCd] = []
  }
}

function codeName(grpCd, value) {
  const c = codes[grpCd].find(item => item.COM_CD === value)
  return c?.DISPLAY_NM || c?.COM_NM || value || '-'
}

const message = ref('')
const messageKind = ref('info')

function notify(text, kind = 'info') {
  message.value = text
  messageKind.value = kind
}

function fail(e, fallback) {
  const err = actionError(e, fallback)
  notify(err.message + (err.code ? ` (${err.code})` : ''), 'error')
  return err
}

/* ================= Grid: 프로토콜 그룹 (GRP_SEARCH) ================= */
const groupColumns = [
  { field: 'ptlGrpCd', label: '그룹코드' },
  { field: 'ptlGrpNm', label: '그룹명' },
  { field: 'protocolCount', label: '프로토콜', align: 'num' },
  { field: 'useYn', label: '사용', code: 'YENO' }
]
const groupQuery = reactive({ keyword: '', includeInactive: false })
const groups = ref([])
const groupLoading = ref(false)
const selectedGroup = ref(null)

async function searchGroups(keepCode) {
  groupLoading.value = true
  try {
    const r = await call('GRP_SEARCH', compact({
      keyword: groupQuery.keyword,
      useYn: groupQuery.includeInactive ? ALL : ''
    }, ['keyword', 'useYn']))
    groups.value = r.data?.items || []
    const code = keepCode ?? selectedGroup.value?.ptlGrpCd
    const again = groups.value.find(g => g.ptlGrpCd === code)
    if (again) {
      selectedGroup.value = again
    } else {
      selectedGroup.value = null
      protocols.value = []
      closeForm()
    }
  } catch (e) {
    groups.value = []
    fail(e, '프로토콜 그룹 조회에 실패했습니다.')
  } finally {
    groupLoading.value = false
  }
}

async function selectGroup(row) {
  selectedGroup.value = row
  closeForm()
  await searchProtocols()
}

/* ================= Dialog: 그룹 등록·수정 (GRP_GET / GRP_CREATE / GRP_UPDATE) ================= */
const groupFields = [
  { field: 'ptlGrpCd', label: '그룹코드', required: true, max: 16, key: true },
  { field: 'ptlGrpNm', label: '그룹명', required: true, max: 100 },
  { field: 'ptlGrpDesc', label: '설명', max: 500, wide: true },
  { field: 'pollingIntval', label: 'Polling 간격(ms)', number: true },
  { field: 'timeoutMs', label: 'Timeout(ms)', number: true },
  { field: 'retryCnt', label: '재시도 횟수', number: true },
  { field: 'sortOrd', label: '정렬순서', number: true }
]
const groupNumberFields = groupFields.filter(f => f.number).map(f => f.field)
const dialog = reactive({ open: false, mode: 'create', model: {}, errors: {}, saving: false, useYn: YES })

function openGroupCreate() {
  dialog.mode = 'create'
  dialog.model = {}
  dialog.errors = {}
  dialog.useYn = YES
  dialog.open = true
}

async function openGroupEdit() {
  if (!selectedGroup.value) return
  try {
    const r = await call('GRP_GET', { ptlGrpCd: selectedGroup.value.ptlGrpCd })
    dialog.mode = 'update'
    dialog.model = { ...r.data }
    dialog.errors = {}
    dialog.useYn = r.data.useYn
    dialog.open = true
  } catch (e) {
    fail(e, '프로토콜 그룹 상세 조회에 실패했습니다.')
  }
}

async function saveGroup(reactivate = false) {
  dialog.saving = true
  dialog.errors = {}
  const fields = groupFields.map(f => f.field)
  const params = compact(dialog.model, fields, groupNumberFields)
  if (reactivate) params.useYn = YES
  try {
    const r = await call(dialog.mode === 'create' ? 'GRP_CREATE' : 'GRP_UPDATE', params)
    dialog.open = false
    notify(dialog.mode === 'create'
      ? `그룹 ${r.data.ptlGrpCd}을(를) 등록했습니다. 기본 프로토콜 ${r.data.ptlGrpCd}0000이 함께 만들어졌습니다.`
      : `그룹 ${r.data.ptlGrpCd}을(를) 저장했습니다.`)
    await searchGroups(r.data.ptlGrpCd)
    if (selectedGroup.value) await searchProtocols()
  } catch (e) {
    dialog.errors = fail(e, '프로토콜 그룹 저장에 실패했습니다.').fieldErrors
  } finally {
    dialog.saving = false
  }
}

async function deleteGroup() {
  const g = selectedGroup.value
  if (!g) return
  if (!window.confirm(`그룹 ${g.ptlGrpCd}와 하위 프로토콜·패킷을 모두 삭제(사용안함)합니다. 계속할까요?`)) return
  try {
    await call('GRP_DELETE', { ptlGrpCd: g.ptlGrpCd })
    notify(`그룹 ${g.ptlGrpCd}을(를) 삭제했습니다.`)
    await searchGroups()
  } catch (e) {
    fail(e, '프로토콜 그룹 삭제에 실패했습니다.')
  }
}

/* ================= Grid: 프로토콜 (SEARCH) ================= */
const protocolColumns = [
  { field: 'ptlCd', label: '프로토콜코드' },
  { field: 'ptlNm', label: '프로토콜명' },
  { field: 'ptlType', label: '유형', code: 'PROT' },
  { field: 'ptlLen', label: '길이', align: 'num' },
  { field: 'packetCount', label: '패킷', align: 'num' },
  { field: 'useYn', label: '사용', code: 'YENO' }
]
const protocolQuery = reactive({ keyword: '', includeInactive: false })
const protocols = ref([])
const protocolLoading = ref(false)

async function searchProtocols() {
  if (!selectedGroup.value) return
  protocolLoading.value = true
  try {
    const r = await call('SEARCH', compact({
      ptlGrpCd: selectedGroup.value.ptlGrpCd,
      keyword: protocolQuery.keyword,
      useYn: protocolQuery.includeInactive ? ALL : ''
    }, ['ptlGrpCd', 'keyword', 'useYn']))
    protocols.value = r.data?.items || []
  } catch (e) {
    protocols.value = []
    fail(e, '프로토콜 조회에 실패했습니다.')
  } finally {
    protocolLoading.value = false
  }
}

/* ================= Form: 프로토콜 상세 (GET / CREATE / UPDATE / DELETE) ================= */
const protocolFields = [
  { field: 'ptlCd', label: '프로토콜코드', required: true, max: 20, key: true },
  { field: 'ptlNm', label: '프로토콜명', required: true, max: 100 },
  { field: 'ptlType', label: '유형', required: true, code: 'PROT' },
  { field: 'ptlLen', label: '길이', number: true },
  { field: 'ptlVal', label: '프로토콜 값', max: 4000, wide: true },
  { field: 'ptlDesc', label: '설명', max: 500, wide: true }
]
const packetColumns = [
  { field: 'packetSeq', label: '순번', number: true, required: true, width: '64px' },
  { field: 'packetType', label: '패킷유형', max: 30 },
  { field: 'direction', label: '방향', required: true, options: ['TX', 'RX'], width: '80px' },
  { field: 'packetExpr', label: '패킷식', max: 4000 },
  { field: 'responsePtlCd', label: '응답 프로토콜', max: 20 },
  { field: 'parseRule', label: '해석규칙', max: 4000 },
  { field: 'dataCount', label: '데이터수', number: true, width: '72px' },
  { field: 'dataType', label: '데이터형', max: 30 },
  { field: 'dataPosition', label: '데이터위치', max: 100 }
]
const packetFieldNames = packetColumns.map(c => c.field)
const packetNumberFields = packetColumns.filter(c => c.number).map(c => c.field)

const form = reactive({ open: false, mode: 'create', model: {}, packets: [], errors: {}, saving: false, loading: false, useYn: YES })
const formEditable = computed(() => form.mode === 'create' ? perm.value.create : perm.value.update)

function closeForm() {
  form.open = false
  form.model = {}
  form.packets = []
  form.errors = {}
}

function openProtocolCreate() {
  if (!selectedGroup.value) return
  form.mode = 'create'
  form.model = { ptlType: 'PROT0000' }
  form.packets = []
  form.errors = {}
  form.useYn = YES
  form.open = true
}

async function selectProtocol(row) {
  form.loading = true
  try {
    const r = await call('GET', { ptlGrpCd: row.ptlGrpCd, ptlCd: row.ptlCd })
    form.mode = 'update'
    form.model = { ...r.data }
    form.packets = (r.data.packets || []).map(p => ({ ...p }))
    form.errors = {}
    form.useYn = r.data.useYn
    form.open = true
  } catch (e) {
    fail(e, '프로토콜 상세 조회에 실패했습니다.')
  } finally {
    form.loading = false
  }
}

function addPacket() {
  const next = form.packets.reduce((m, p) => Math.max(m, Number(p.packetSeq) || 0), 0) + 1
  form.packets.push({ packetSeq: next, direction: 'TX' })
}

function removePacket(index) {
  form.packets.splice(index, 1)
}

async function saveProtocol(reactivate = false) {
  form.saving = true
  form.errors = {}
  const fields = protocolFields.map(f => f.field)
  const params = {
    ptlGrpCd: selectedGroup.value.ptlGrpCd,
    ...compact(form.model, fields, ['ptlLen']),
    // 보내면 서버가 패킷을 전체 교체한다. 출력 전용 필드(useYn)는 보내지 않는다.
    packets: form.packets.map(p => compact(p, packetFieldNames, packetNumberFields))
  }
  if (reactivate) params.useYn = YES
  try {
    const r = await call(form.mode === 'create' ? 'CREATE' : 'UPDATE', params)
    notify(`프로토콜 ${r.data.ptlCd}을(를) 저장했습니다.`)
    await searchProtocols()
    await searchGroups(r.data.ptlGrpCd)
    await selectProtocol(r.data)
  } catch (e) {
    form.errors = fail(e, '프로토콜 저장에 실패했습니다.').fieldErrors
  } finally {
    form.saving = false
  }
}

async function deleteProtocol() {
  const m = form.model
  if (!window.confirm(`프로토콜 ${m.ptlCd}와 패킷을 삭제(사용안함)합니다. 계속할까요?`)) return
  try {
    await call('DELETE', { ptlGrpCd: m.ptlGrpCd, ptlCd: m.ptlCd })
    notify(`프로토콜 ${m.ptlCd}을(를) 삭제했습니다.`)
    closeForm()
    await searchProtocols()
    await searchGroups()
  } catch (e) {
    fail(e, '프로토콜 삭제에 실패했습니다.')
  }
}

function cell(row, col) {
  const v = row[col.field]
  return col.code ? codeName(col.code, v) : (v ?? '-')
}

onMounted(async () => {
  await Promise.all([loadCode('PROT'), loadCode('YENO')])
  await searchGroups()
})
</script>

<template>
  <section class="page">
    <div class="head">
      <h2>프로토콜관리</h2>
      <p>프로토콜 그룹과 프로토콜·패킷을 관리합니다. 삭제는 사용안함 처리이며, 장치·실험에서 사용 중이면 삭제할 수 없습니다.</p>
    </div>

    <p v-if="message" :class="['msg', messageKind]" data-test="message">{{ message }}</p>

    <div class="layout">
      <!-- Grid: 프로토콜 그룹 -->
      <div class="box groups" data-test="group-grid">
        <div class="box-head">
          <strong>프로토콜 그룹</strong>
          <span class="buttons">
            <button v-if="perm.create" data-test="group-new" @click="openGroupCreate">신규</button>
            <button v-if="perm.update" data-test="group-edit" :disabled="!selectedGroup" @click="openGroupEdit">수정</button>
            <button v-if="perm.remove" data-test="group-delete" class="danger" :disabled="!selectedGroup || selectedGroup.useYn !== YES" @click="deleteGroup">삭제</button>
          </span>
        </div>
        <div class="search">
          <input v-model="groupQuery.keyword" placeholder="그룹코드 또는 그룹명" @keyup.enter="searchGroups()">
          <label><input v-model="groupQuery.includeInactive" type="checkbox" @change="searchGroups()"> 사용안함 포함</label>
          <button :disabled="groupLoading" @click="searchGroups()">조회</button>
        </div>
        <table>
          <thead><tr><th v-for="c in groupColumns" :key="c.field" :class="c.align">{{ c.label }}</th></tr></thead>
          <tbody>
            <tr v-if="!groups.length" class="empty"><td :colspan="groupColumns.length">{{ groupLoading ? '조회중...' : '그룹이 없습니다.' }}</td></tr>
            <tr v-for="g in groups" :key="g.ptlGrpCd"
                :class="{ selected: selectedGroup?.ptlGrpCd === g.ptlGrpCd, inactive: g.useYn !== YES }"
                @click="selectGroup(g)">
              <td v-for="c in groupColumns" :key="c.field" :class="c.align">{{ cell(g, c) }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="right">
        <!-- Grid: 프로토콜 -->
        <div class="box" data-test="protocol-grid">
          <div class="box-head">
            <strong>프로토콜 <span v-if="selectedGroup" class="sub">{{ selectedGroup.ptlGrpCd }} · {{ selectedGroup.ptlGrpNm }}</span></strong>
            <span class="buttons">
              <button v-if="perm.create" data-test="protocol-new" :disabled="!selectedGroup || selectedGroup.useYn !== YES" @click="openProtocolCreate">신규</button>
            </span>
          </div>
          <div v-if="selectedGroup" class="search">
            <input v-model="protocolQuery.keyword" placeholder="프로토콜코드 또는 프로토콜명" @keyup.enter="searchProtocols">
            <label><input v-model="protocolQuery.includeInactive" type="checkbox" @change="searchProtocols"> 사용안함 포함</label>
            <button :disabled="protocolLoading" @click="searchProtocols">조회</button>
          </div>
          <table>
            <thead><tr><th v-for="c in protocolColumns" :key="c.field" :class="c.align">{{ c.label }}</th></tr></thead>
            <tbody>
              <tr v-if="!selectedGroup" class="empty"><td :colspan="protocolColumns.length">왼쪽에서 그룹을 선택하세요.</td></tr>
              <tr v-else-if="!protocols.length" class="empty"><td :colspan="protocolColumns.length">{{ protocolLoading ? '조회중...' : '프로토콜이 없습니다.' }}</td></tr>
              <tr v-for="p in protocols" :key="p.ptlCd"
                  :class="{ selected: form.open && form.mode === 'update' && form.model.ptlCd === p.ptlCd, inactive: p.useYn !== YES }"
                  @click="selectProtocol(p)">
                <td v-for="c in protocolColumns" :key="c.field" :class="c.align">{{ cell(p, c) }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Form: 프로토콜 상세 + 패킷 Grid -->
        <div v-if="form.open" class="box" data-test="protocol-form">
          <div class="box-head">
            <strong>{{ form.mode === 'create' ? '프로토콜 등록' : '프로토콜 상세' }}</strong>
            <span class="buttons">
              <button v-if="formEditable && form.useYn === YES" data-test="protocol-save" :disabled="form.saving" @click="saveProtocol()">저장</button>
              <button v-if="form.mode === 'update' && perm.update && form.useYn !== YES" data-test="protocol-reactivate" :disabled="form.saving" @click="saveProtocol(true)">다시 사용</button>
              <button v-if="form.mode === 'update' && perm.remove && form.useYn === YES" data-test="protocol-delete" class="danger" @click="deleteProtocol">삭제</button>
              <button @click="closeForm">닫기</button>
            </span>
          </div>
          <div class="form">
            <label v-for="f in protocolFields" :key="f.field" :class="{ wide: f.wide }">
              <span>{{ f.label }}<em v-if="f.required">*</em></span>
              <select v-if="f.code" v-model="form.model[f.field]" :disabled="!formEditable" :data-field="f.field">
                <option v-for="c in codes[f.code]" :key="c.COM_CD" :value="c.COM_CD">{{ c.DISPLAY_NM || c.COM_NM }}</option>
              </select>
              <textarea v-else-if="f.wide && f.max > 500" v-model="form.model[f.field]" :maxlength="f.max" :disabled="!formEditable" :data-field="f.field" rows="2" />
              <input v-else v-model="form.model[f.field]" :type="f.number ? 'number' : 'text'" :maxlength="f.max"
                     :disabled="!formEditable || (f.key && form.mode === 'update')" :data-field="f.field">
              <small v-if="form.errors[f.field]" class="field-error">{{ form.errors[f.field] }}</small>
            </label>
          </div>
          <div class="packet-head">
            <strong>패킷</strong>
            <button v-if="formEditable" data-test="packet-add" @click="addPacket">패킷 추가</button>
          </div>
          <small v-if="form.errors.packets" class="field-error">{{ form.errors.packets }}</small>
          <table class="packets">
            <thead>
              <tr>
                <th v-for="c in packetColumns" :key="c.field" :style="{ width: c.width }">{{ c.label }}<em v-if="c.required">*</em></th>
                <th v-if="formEditable" />
              </tr>
            </thead>
            <tbody>
              <tr v-if="!form.packets.length" class="empty"><td :colspan="packetColumns.length + 1">패킷이 없습니다.</td></tr>
              <tr v-for="(p, i) in form.packets" :key="i">
                <td v-for="c in packetColumns" :key="c.field">
                  <select v-if="c.options" v-model="p[c.field]" :disabled="!formEditable">
                    <option v-for="o in c.options" :key="o" :value="o">{{ o }}</option>
                  </select>
                  <input v-else v-model="p[c.field]" :type="c.number ? 'number' : 'text'" :maxlength="c.max" :disabled="!formEditable"
                         :data-field="`packets[${i}].${c.field}`">
                  <small v-if="form.errors[`packets[${i}].${c.field}`]" class="field-error">{{ form.errors[`packets[${i}].${c.field}`] }}</small>
                </td>
                <td v-if="formEditable"><button class="link" @click="removePacket(i)">삭제</button></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- Dialog: 그룹 등록·수정 -->
    <div v-if="dialog.open" class="dialog-backdrop" @click.self="dialog.open = false">
      <div class="dialog" data-test="group-dialog">
        <div class="box-head">
          <strong>{{ dialog.mode === 'create' ? '프로토콜 그룹 등록' : '프로토콜 그룹 수정' }}</strong>
        </div>
        <div class="form">
          <label v-for="f in groupFields" :key="f.field" :class="{ wide: f.wide }">
            <span>{{ f.label }}<em v-if="f.required && (dialog.mode === 'create' || f.key)">*</em></span>
            <input v-model="dialog.model[f.field]" :type="f.number ? 'number' : 'text'" :maxlength="f.max"
                   :disabled="(f.key && dialog.mode === 'update') || dialog.useYn !== YES" :data-field="f.field">
            <small v-if="dialog.errors[f.field]" class="field-error">{{ dialog.errors[f.field] }}</small>
          </label>
        </div>
        <p v-if="dialog.mode === 'create'" class="hint">등록하면 기본 프로토콜 <code>{그룹코드}0000</code>(기본 TX/RX)이 함께 만들어집니다.</p>
        <div class="dialog-buttons">
          <button v-if="dialog.useYn === YES" data-test="group-save" :disabled="dialog.saving" @click="saveGroup()">저장</button>
          <button v-else data-test="group-reactivate" :disabled="dialog.saving" @click="saveGroup(true)">다시 사용</button>
          <button @click="dialog.open = false">취소</button>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.page { padding: 20px; }
.head h2 { margin-bottom: 6px; }
.head p { margin: 0; color: #667085; }
.msg { margin: 12px 0 0; padding: 8px 12px; border-radius: 4px; background: #eef4ff; color: #1d3f8a; }
.msg.error { background: #fdecec; color: #a12020; }
.layout { display: grid; grid-template-columns: minmax(280px, 1fr) 2fr; gap: 16px; margin-top: 16px; align-items: start; }
.right { display: flex; flex-direction: column; gap: 16px; min-width: 0; }
.box { background: #fff; border: 1px solid #d9e0e8; overflow: auto; }
.box-head { display: flex; justify-content: space-between; align-items: center; padding: 10px 12px; border-bottom: 1px solid #e5e9ef; background: #fafbfc; }
.box-head .sub { margin-left: 8px; font-weight: normal; color: #667085; }
.buttons { display: flex; gap: 6px; }
.search { display: flex; gap: 8px; align-items: center; padding: 10px 12px; }
.search input[type="text"], .search input:not([type]) { flex: 1; min-width: 0; }
.search label { white-space: nowrap; font-size: 13px; color: #475467; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 8px; border-bottom: 1px solid #e5e9ef; text-align: left; font-size: 14px; }
th { background: #f5f7fa; }
td.num, th.num { text-align: right; }
tbody tr:not(.empty) { cursor: pointer; }
tbody tr:hover { background: #f7f9fc; }
tbody tr.selected { background: #eaf2ff; }
tbody tr.inactive td { color: #98a2b3; }
tr.empty td { color: #98a2b3; text-align: center; cursor: default; }
.form { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px 16px; padding: 12px; }
.form label { display: flex; flex-direction: column; gap: 4px; font-size: 13px; color: #344054; }
.form label.wide { grid-column: 1 / -1; }
.form input, .form select, .form textarea { padding: 6px 8px; font-size: 14px; }
em { color: #d92d20; font-style: normal; margin-left: 2px; }
.field-error { color: #d92d20; font-size: 12px; }
.packet-head { display: flex; justify-content: space-between; align-items: center; padding: 8px 12px; border-top: 1px solid #e5e9ef; }
.packets td { vertical-align: top; cursor: default; }
.packets input, .packets select { width: 100%; box-sizing: border-box; padding: 4px 6px; }
button.danger { color: #b42318; }
button.link { background: none; border: none; color: #b42318; cursor: pointer; padding: 0; }
.dialog-backdrop { position: fixed; inset: 0; background: rgba(16, 24, 40, 0.4); display: flex; align-items: center; justify-content: center; z-index: 10; }
.dialog { background: #fff; width: min(640px, calc(100vw - 32px)); border-radius: 6px; overflow: hidden; }
.dialog .hint { margin: 0 12px; font-size: 13px; color: #667085; }
.dialog-buttons { display: flex; justify-content: flex-end; gap: 8px; padding: 12px; }
@media (max-width: 900px) { .layout { grid-template-columns: 1fr; } .form { grid-template-columns: 1fr; } }
</style>
