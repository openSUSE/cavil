<template>
  <div id="pending-actions-widget" :class="['pending-actions-widget', {expanded}]">
    <button
      v-if="!expanded"
      type="button"
      class="pending-actions-toggle btn btn-success"
      @click="expanded = true"
      :disabled="submitting"
    >
      <i class="fa-solid fa-list-check"></i>
      Pending changes
      <span class="badge text-bg-light ms-1">{{ store.actions.length }}</span>
    </button>
    <div v-else class="pending-actions-panel">
      <div class="pending-actions-header">
        <span>
          <i class="fa-solid fa-list-check"></i>
          Pending changes
          <span class="badge text-bg-secondary ms-1">{{ store.actions.length }}</span>
        </span>
        <button type="button" class="btn-close" aria-label="Collapse" @click="expanded = false"></button>
      </div>
      <ul class="pending-actions-list">
        <li v-for="action in store.actions" :key="action.id" :class="['pending-actions-item', `state-${action.state}`]">
          <div class="pending-actions-item-main">
            <div class="pending-actions-item-label">
              <i :class="['fa-solid', stateIcon(action.state)]"></i>
              <strong>{{ actionLabel(action.action) }}</strong>
              <span v-if="action.license" class="pending-actions-license">· {{ action.license }}</span>
            </div>
            <a
              href="#"
              class="pending-actions-item-meta pending-actions-item-link"
              @click.prevent="onJumpTo(action)"
              :title="`Scroll to ${action.locationLabel}`"
            >
              <i class="fa-solid fa-location-crosshairs"></i>
              {{ action.locationLabel }}
            </a>
            <div v-if="action.error" class="pending-actions-item-error">{{ action.error }}</div>
          </div>
          <div v-if="action.state !== 'submitting' && action.state !== 'done'" class="pending-actions-controls">
            <button
              type="button"
              class="btn btn-sm btn-link"
              @click="store.edit(action.id)"
              :disabled="submitting"
              title="Edit"
              data-action-control="edit"
            >
              <i class="fa-solid fa-pen-to-square"></i>
            </button>
            <button
              type="button"
              class="btn btn-sm btn-link"
              @click="store.remove(action.id)"
              :disabled="submitting"
              title="Remove from batch"
              data-action-control="remove"
            >
              <i class="fa-solid fa-trash"></i>
            </button>
          </div>
        </li>
      </ul>
      <div class="pending-actions-footer">
        <button
          type="button"
          class="btn btn-success"
          :disabled="submitting || !pendingCount"
          @click="onSubmit"
          id="pending-actions-submit"
        >
          <i v-if="submitting" class="fa-solid fa-spinner fa-pulse"></i>
          <i v-else class="fa-solid fa-paper-plane"></i>
          {{ submitting ? 'Submitting...' : `Submit ${pendingCount} change${pendingCount === 1 ? '' : 's'}` }}
        </button>
        <button
          type="button"
          class="btn btn-outline-secondary ms-2"
          :disabled="submitting"
          @click="store.clear()"
          title="Clear all"
        >
          Clear
        </button>
      </div>
    </div>
  </div>
</template>

<script>
const ACTION_LABELS = {
  'create-pattern': 'Create pattern',
  'create-ignore': 'Create ignore',
  'mark-non-license': 'Mark non-license',
  'propose-pattern': 'Propose pattern',
  'propose-ignore': 'Propose ignore',
  'propose-glob': 'Propose ignore glob',
  'propose-missing': 'Propose missing license'
};

export default {
  name: 'PendingActionsWidget',
  inject: ['pendingActionsStore'],
  data() {
    return {
      expanded: false
    };
  },
  computed: {
    store() {
      return this.pendingActionsStore;
    },
    submitting() {
      return this.store.actions.some(a => a.state === 'submitting');
    },
    pendingCount() {
      return this.store.actions.filter(a => a.state !== 'done').length;
    }
  },
  watch: {
    'store.actions.length'(n) {
      if (n === 0) this.expanded = false;
    }
  },
  methods: {
    actionLabel(kind) {
      return ACTION_LABELS[kind] ?? kind;
    },
    stateIcon(state) {
      if (state === 'submitting') return 'fa-spinner fa-pulse';
      if (state === 'done') return 'fa-circle-check';
      if (state === 'error') return 'fa-circle-exclamation';
      return 'fa-clock';
    },
    async onSubmit() {
      await this.store.submitAll();
    },
    onJumpTo(action) {
      this.expanded = false;
      this.store.scrollTo(action.id);
    }
  }
};
</script>

<style>
.pending-actions-widget {
  position: fixed;
  bottom: 20px;
  right: 72px;
  z-index: 1040;
  font-size: 13px;
}
.pending-actions-toggle {
  box-shadow: 0 4px 12px rgba(27, 31, 36, 0.3);
}
.pending-actions-panel {
  background: white;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(140, 149, 159, 0.3);
  width: 380px;
  max-height: 70vh;
  display: flex;
  flex-direction: column;
}
.pending-actions-header {
  padding: 12px 16px;
  border-bottom: 1px solid #d0d7de;
  background: #f6f8fa;
  border-radius: 6px 6px 0 0;
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-weight: 600;
}
.pending-actions-list {
  list-style: none;
  margin: 0;
  padding: 0;
  overflow-y: auto;
  flex: 1;
}
.pending-actions-item {
  padding: 10px 16px;
  border-bottom: 1px solid #eaeef2;
  display: flex;
  align-items: flex-start;
  gap: 8px;
}
.pending-actions-item:last-child {
  border-bottom: 0;
}
.pending-actions-item-main {
  flex: 1;
  min-width: 0;
}
.pending-actions-controls {
  display: flex;
  gap: 0;
}
.pending-actions-controls .btn {
  padding: 0.125rem 0.375rem;
  color: #59636e;
  text-decoration: none;
}
.pending-actions-controls .btn:hover {
  color: #1f2328;
}
.pending-actions-controls .btn:disabled {
  color: #8c959f;
}
.pending-actions-item-label {
  display: flex;
  align-items: center;
  gap: 6px;
}
.pending-actions-license {
  color: #57606a;
  font-size: 12px;
}
.pending-actions-item-meta {
  color: #57606a;
  font-size: 11px;
  margin-top: 2px;
  word-break: break-all;
}
.pending-actions-item-link {
  display: inline-flex;
  align-items: baseline;
  gap: 4px;
  text-decoration: none;
}
.pending-actions-item-link:hover {
  color: #0969da;
  text-decoration: underline;
}
.pending-actions-item-link i {
  font-size: 10px;
  flex-shrink: 0;
}
.pending-actions-item.state-done .pending-actions-item-link {
  pointer-events: none;
  opacity: 0.6;
}
.pending-actions-item-error {
  color: #cf222e;
  font-size: 11px;
  margin-top: 4px;
}
.pending-actions-item.state-done .pending-actions-item-label {
  color: #1a7f37;
}
.pending-actions-item.state-error .pending-actions-item-label {
  color: #cf222e;
}
.pending-actions-footer {
  padding: 12px 16px;
  border-top: 1px solid #d0d7de;
  background: #f6f8fa;
  border-radius: 0 0 6px 6px;
}
</style>
