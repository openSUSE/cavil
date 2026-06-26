<template>
  <span v-if="priority >= 8" class="priority-badge priority-badge-danger" :title="`Priority ${priority}`">
    {{ priority }}
  </span>
  <span v-else-if="priority >= 5" class="priority-badge priority-badge-warning" :title="`Priority ${priority}`">
    {{ priority }}
  </span>
  <span v-else class="priority-badge priority-badge-success" :title="`Priority ${priority}`">
    {{ priority }}
  </span>
</template>

<script>
export default {
  name: 'PriorityBadge',
  props: {
    priority: {type: Number, required: true}
  }
};
</script>

<style>
.priority-badge {
  align-items: center;
  backdrop-filter: blur(8px) saturate(1.15);
  background:
    linear-gradient(145deg, rgba(255, 255, 255, 0.78), rgba(255, 255, 255, 0.34)),
    linear-gradient(145deg, var(--priority-glass), var(--priority-glass-strong));
  border: 1px solid var(--priority-border);
  border-radius: 999px;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.9),
    inset 0 -1px 0 rgba(27, 31, 36, 0.08),
    0 1px 2px rgba(27, 31, 36, 0.08);
  color: var(--priority-text);
  display: inline-flex;
  font-size: 1rem;
  font-weight: 700;
  height: 2rem;
  justify-content: center;
  letter-spacing: 0;
  line-height: 1;
  min-width: 0;
  padding: 0;
  text-align: center;
  text-shadow:
    0 1px 0 rgba(255, 255, 255, 0.65),
    0 -1px 0 rgba(27, 31, 36, 0.12);
  width: 2rem;
}

.priority-badge-danger {
  --priority-border: rgba(207, 34, 46, 0.45);
  --priority-glass: rgba(207, 34, 46, 0.2);
  --priority-glass-strong: rgba(207, 34, 46, 0.34);
  --priority-text: #a40e26;
}

.priority-badge-warning {
  --priority-border: rgba(240, 180, 0, 0.52);
  --priority-glass: rgba(240, 180, 0, 0.24);
  --priority-glass-strong: rgba(240, 180, 0, 0.4);
  --priority-text: #6f4e00;
}

.priority-badge-success {
  --priority-border: rgba(26, 127, 55, 0.45);
  --priority-glass: rgba(26, 127, 55, 0.18);
  --priority-glass-strong: rgba(26, 127, 55, 0.32);
  --priority-text: #116329;
}
</style>
