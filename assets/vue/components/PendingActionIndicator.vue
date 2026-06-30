<template>
  <span :id="'pending-indicator-' + action.id" class="pending-action-badge" :title="title">
    <button v-if="canEdit" type="button" class="pending-action-edit" @click.stop.prevent="store.edit(action.id)">
      <i class="fa-solid fa-clock"></i>
      {{ shortLabel }}
    </button>
    <span v-else class="pending-action-label">
      <i class="fa-solid fa-clock"></i>
      {{ shortLabel }}
    </span>
    <button
      type="button"
      class="pending-action-dismiss"
      aria-label="Dismiss"
      @click.stop.prevent="$emit('dismiss', action)"
    >
      <i class="fa-solid fa-xmark"></i>
    </button>
  </span>
</template>

<script>
const ACTION_LABELS = {
  'create-pattern': 'Pattern queued',
  'create-ignore': 'Ignore queued',
  'mark-non-license': 'No-legal queued',
  'propose-pattern': 'Proposal queued',
  'propose-ignore': 'Ignore proposal queued',
  'propose-missing': 'Missing-license queued'
};

export default {
  name: 'PendingActionIndicator',
  inject: ['pendingActionsStore'],
  props: {
    action: {type: Object, required: true}
  },
  emits: ['dismiss'],
  computed: {
    store() {
      return this.pendingActionsStore;
    },
    canEdit() {
      return this.action.state !== 'submitting' && this.action.state !== 'done';
    },
    shortLabel() {
      return ACTION_LABELS[this.action.action] ?? 'Queued';
    },
    title() {
      const lic = this.action.license ? ` — ${this.action.license}` : '';
      const err = this.action.error ? ` (error: ${this.action.error})` : '';
      return `${this.shortLabel}${lic}${err}`;
    }
  }
};
</script>

<style>
.pending-action-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.4em;
  background: #fff8c5;
  border: 1px solid rgba(212, 167, 44, 0.4);
  color: #57606a;
  font-size: 11px;
  font-weight: 500;
  padding: 1px 6px;
  border-radius: 12px;
  margin-left: 4px;
  line-height: 1.4;
  white-space: nowrap;
}
.pending-action-badge.has-error {
  background: #ffebe9;
  border-color: rgba(207, 34, 46, 0.4);
  color: #82071e;
}
.pending-action-edit,
.pending-action-label {
  align-items: center;
  color: inherit;
  display: inline-flex;
  gap: 0.4em;
  line-height: inherit;
}
.pending-action-edit {
  background: transparent;
  border: 0;
  cursor: pointer;
  font: inherit;
  padding: 0;
}
.pending-action-edit:hover {
  color: #1f2328;
  text-decoration: underline;
}
.pending-action-dismiss {
  background: transparent;
  border: 0;
  padding: 0 2px;
  color: inherit;
  cursor: pointer;
  font-size: 11px;
  line-height: 1;
}
.pending-action-dismiss:hover {
  color: #cf222e;
}
</style>
