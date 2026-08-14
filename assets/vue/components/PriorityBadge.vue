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
    linear-gradient(145deg, var(--cavil-badge-gloss-top), var(--cavil-badge-gloss-bottom)),
    linear-gradient(145deg, var(--priority-glass), var(--priority-glass-strong));
  border: 1px solid var(--priority-border);
  border-radius: 999px;
  box-shadow:
    inset 0 1px 0 var(--cavil-badge-rim),
    inset 0 -1px 0 rgba(var(--cavil-shadow-rgb), 0.08),
    0 1px 2px rgba(var(--cavil-shadow-rgb), 0.08);
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
    0 1px 0 var(--cavil-badge-text-shadow),
    0 -1px 0 rgba(var(--cavil-shadow-rgb), 0.12);
  width: 2rem;
}

.priority-badge-danger {
  --priority-border: rgba(var(--cavil-danger-rgb), 0.68);
  --priority-glass: rgba(var(--cavil-danger-rgb), 0.34);
  --priority-glass-strong: rgba(var(--cavil-danger-rgb), 0.56);
  --priority-text: var(--cavil-danger-3);
}

.priority-badge-warning {
  --priority-border: rgba(var(--cavil-attention-vivid-rgb), 0.76);
  --priority-glass: rgba(var(--cavil-attention-vivid-rgb), 0.38);
  --priority-glass-strong: rgba(var(--cavil-attention-vivid-rgb), 0.62);
  --priority-text: var(--cavil-attention-deep-3);
}

.priority-badge-success {
  --priority-border: rgba(var(--cavil-success-rgb), 0.68);
  --priority-glass: rgba(var(--cavil-success-rgb), 0.32);
  --priority-glass-strong: rgba(var(--cavil-success-rgb), 0.54);
  --priority-text: var(--cavil-success-deep);
}

/* Light stacks a pale tint under dark text; dark inverts that to a low tint under light
   text, so the glass has to thin out or the pill swamps its own number. */
[data-bs-theme='dark'] .priority-badge-danger {
  --priority-border: rgba(var(--cavil-danger-rgb), 0.5);
  --priority-glass: rgba(var(--cavil-danger-rgb), 0.16);
  --priority-glass-strong: rgba(var(--cavil-danger-rgb), 0.28);
}
[data-bs-theme='dark'] .priority-badge-warning {
  --priority-border: rgba(var(--cavil-attention-vivid-rgb), 0.5);
  --priority-glass: rgba(var(--cavil-attention-vivid-rgb), 0.16);
  --priority-glass-strong: rgba(var(--cavil-attention-vivid-rgb), 0.28);
}
[data-bs-theme='dark'] .priority-badge-success {
  --priority-border: rgba(var(--cavil-success-rgb), 0.5);
  --priority-glass: rgba(var(--cavil-success-rgb), 0.16);
  --priority-glass-strong: rgba(var(--cavil-success-rgb), 0.28);
}
</style>
