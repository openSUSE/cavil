<template>
  <section id="status">
    <div class="cavil-settings-header">
      <h3>Status</h3>
      <p>
        What Cavil found when checking this instance as the page loaded. The same checks run on the command line with
        <code>script/cavil doctor</code>, which is handy before the web application is reachable.
      </p>
    </div>

    <section class="cavil-list-panel">
      <div class="cavil-list-header">
        <div class="cavil-list-title">
          <i class="fa-solid fa-heart-pulse" aria-hidden="true"></i>
          <span>{{ summary }}</span>
        </div>
      </div>
      <div class="cavil-list-table-wrap">
        <table class="cavil-list-table table">
          <tbody v-if="checks === null">
            <tr>
              <td colspan="2" class="cavil-list-state">
                <LegalLoading message="Checking..." size="small" />
              </td>
            </tr>
          </tbody>
          <tbody v-else>
            <tr v-for="check in checks" :key="check.name">
              <td :class="['cavil-status-name', `cavil-status-${check.level}`]">{{ check.name }}</td>
              <td>{{ check.message }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </section>
</template>

<script>
import LegalLoading from './LegalLoading.vue';
import Refresh from '../mixins/refresh.js';

export default {
  name: 'SettingsStatus',
  components: {LegalLoading},
  mixins: [Refresh],
  data() {
    return {checks: null, refreshDelay: 0, refreshUrl: '/settings/status.json'};
  },
  computed: {
    summary() {
      if (this.checks === null) return 'Checking';
      const problems = this.checks.filter(check => check.level !== 'ok').length;
      if (problems === 0) return 'All checks passed';
      return problems === 1 ? '1 check needs attention' : `${problems} checks need attention`;
    }
  },
  methods: {
    refreshData(data) {
      this.checks = data.checks;
    }
  }
};
</script>

<style>
.cavil-list-table tbody td.cavil-status-name {
  font-weight: 600;
  padding-left: 2rem;
  position: relative;
  white-space: nowrap;
  width: 1%;
}
.cavil-status-name::before {
  border-radius: 50%;
  content: '';
  height: 0.5rem;
  left: 0.85rem;
  position: absolute;
  top: calc(50% - 0.25rem);
  width: 0.5rem;
}
.cavil-status-ok::before {
  background: var(--cavil-success);
}
.cavil-status-warning::before {
  background: var(--cavil-attention-strong);
}
.cavil-status-error::before {
  background: var(--cavil-danger);
}
</style>
