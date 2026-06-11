<template>
  <li class="nav-item dropdown cavil-user-menu">
    <a
      class="nav-link dropdown-toggle"
      href="#"
      role="button"
      data-bs-toggle="dropdown"
      aria-expanded="false"
      aria-label="Open account menu"
      title="Open account menu"
    >
      <i class="fa-regular fa-circle-user cavil-user-menu-icon" aria-hidden="true"></i>
      <span class="cavil-user-name">{{ currentUser }}</span>
      <span v-if="total > 0" :class="totalBadgeClass" class="cavil-menu-badge">{{ total }}</span>
    </a>
    <ul class="dropdown-menu dropdown-menu-end cavil-user-dropdown">
      <template v-if="roles.length > 0">
        <li><h3 class="dropdown-header">Roles</h3></li>
        <li>
          <span class="dropdown-item-text cavil-role-list">
            <span v-for="role in sortedRoles" :key="role" class="badge text-bg-secondary">{{ role }}</span>
          </span>
        </li>
        <li><hr class="dropdown-divider" /></li>
      </template>
      <li><h3 class="dropdown-header">User Menu</h3></li>
      <li>
        <a :href="urls.missing" class="dropdown-item">
          <span>Missing Licenses</span>
          <span v-if="stats.missing > 0" class="badge bg-danger cavil-dropdown-badge">{{ stats.missing }}</span>
        </a>
      </li>
      <li>
        <a :href="urls.proposed" class="dropdown-item">
          <span>Change Proposals</span>
          <span v-if="stats.proposals > 0" class="badge bg-secondary cavil-dropdown-badge">{{ stats.proposals }}</span>
        </a>
      </li>
      <li><a :href="urls.recentPatterns" class="dropdown-item">Pattern Performance</a></li>
      <li><a :href="urls.recentNotes" class="dropdown-item">Recent Notes</a></li>
      <li><a :href="urls.stats" class="dropdown-item">Statistics</a></li>
      <li><hr class="dropdown-divider" /></li>
      <template v-if="hasAdminRole">
        <li><h3 class="dropdown-header">Administrator Menu</h3></li>
        <li><a :href="urls.upload" class="dropdown-item">Upload Tarball</a></li>
        <li><a :href="urls.ignoredMatches" class="dropdown-item">Ignored Matches</a></li>
        <li><a :href="urls.ignoredFiles" class="dropdown-item">Ignored Files</a></li>
        <li><a :href="urls.minion" class="dropdown-item">Minion Dashboard</a></li>
        <li><hr class="dropdown-divider" /></li>
      </template>
      <li><a :href="urls.documentation" class="dropdown-item">Documentation</a></li>
      <li><a :href="urls.apiKeys" class="dropdown-item">API Keys</a></li>
      <li><a :href="urls.logout" class="dropdown-item">Logout</a></li>
    </ul>
  </li>
</template>

<script>
import Refresh from './mixins/refresh.js';

export default {
  name: 'CavilMenu',
  mixins: [Refresh],
  props: {
    currentUser: {type: String, required: true},
    hasAdminRole: {type: Boolean, default: false},
    initialStats: {type: Object, required: true},
    roles: {type: Array, default: () => []},
    urls: {type: Object, required: true}
  },
  data() {
    return {
      refreshDelay: 30000,
      refreshUrl: '/licenses/proposed/stats',
      stats: {...this.initialStats}
    };
  },
  computed: {
    sortedRoles() {
      return [...this.roles].sort();
    },
    total() {
      return this.stats.missing + this.stats.proposals;
    },
    totalBadgeClass() {
      return this.stats.missing > 0 ? 'badge bg-danger' : 'badge bg-secondary';
    }
  },
  methods: {
    refreshData(data) {
      this.stats = {
        missing: Number(data.missing ?? 0),
        proposals: Number(data.proposals ?? 0)
      };
    }
  }
};
</script>
