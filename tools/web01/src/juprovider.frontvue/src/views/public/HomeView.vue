<template>
  <main data-test="home">
    <section class="hero">
      <div class="container">
        <h1>JuProvider</h1>
        <p>DAQ 장치 연결, 프로토콜, 데이터 수집과 실험을 한곳에서 관리하는 데이터 수집 플랫폼입니다.</p>
      </div>
    </section>
    <section class="section">
      <div class="container cards">
        <div class="card">
          <h3>장치 관리</h3>
          <p>Network·Serial·가상 장치를 등록하고 연결 상태를 관리합니다.</p>
        </div>
        <div class="card">
          <h3>프로토콜</h3>
          <p>장치별 송수신 프로토콜과 패킷 구성을 정의합니다.</p>
        </div>
        <div class="card">
          <h3>수집과 실험</h3>
          <p>Desktop Client가 데이터를 수집하고 서버와 동기화합니다.</p>
        </div>
      </div>
    </section>
  </main>
</template>

<style scoped>
.hero p { font-size: 18px; max-width: 640px; line-height: 1.6; color: #d6deea; }
.card h3 { margin: 0 0 8px; }
.card p { margin: 0; color: #475467; line-height: 1.55; }
</style>
