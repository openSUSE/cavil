<template>
  <span class="report-file-actions">
    <span class="dropdown">
      <a
        href="#"
        :id="'file-menu-' + fileId"
        data-bs-toggle="dropdown"
        aria-haspopup="true"
        aria-expanded="false"
        title="File actions"
        aria-label="File actions"
      >
        <i class="fa-solid fa-ellipsis"></i>
      </a>
      <div class="dropdown-menu dropdown-menu-end" :aria-labelledby="'file-menu-' + fileId">
        <a :href="viewUrl" class="dropdown-item" target="_blank" rel="noopener">View file</a>
        <template v-if="hasAdminRole || hasContributorRole">
          <div class="dropdown-divider"></div>
          <a v-if="hasAdminRole" href="#" class="dropdown-item" @click.prevent="$emit('glob', true)"
            >Add ignore glob&hellip;</a
          >
          <a href="#" class="dropdown-item" @click.prevent="$emit('glob', false)">Propose ignore glob&hellip;</a>
        </template>
      </div>
    </span>
    <button type="button" class="report-file-close" title="Close" aria-label="Close" @click="$emit('close')">
      <i class="fa-solid fa-xmark"></i>
    </button>
  </span>
</template>

<script>
// GitHub's file-header "..." menu and a close button, on the report row whose matches are open
export default {
  name: 'ReportFileActions',
  props: {
    fileId: {type: Number, required: true},
    viewUrl: {type: String, required: true},
    hasAdminRole: {type: Boolean, default: false},
    hasContributorRole: {type: Boolean, default: false}
  },
  emits: ['glob', 'close']
};
</script>

<style>
.report-file-actions {
  align-items: center;
  display: inline-flex;
  gap: 0.15rem;
}
.report-file-actions a,
.report-file-close {
  background: none;
  border: 0;
  border-radius: 6px;
  color: var(--cavil-fg-muted);
  font-size: 13px;
  line-height: 1;
  padding: 0.25rem 0.4rem;
}
.report-file-actions a:hover,
.report-file-actions a:focus-visible,
.report-file-close:hover,
.report-file-close:focus-visible {
  background: var(--cavil-canvas-subtle);
  color: var(--cavil-accent-strong);
}
</style>
