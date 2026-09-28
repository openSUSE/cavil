<template>
  <li class="list-more-toggle">
    <button type="button" @click="$emit('toggle')">
      <i :class="expanded ? 'fa-solid fa-chevron-up' : 'fa-solid fa-chevron-down'"></i>
      {{ expanded ? `Show top ${preview}` : `Show ${hidden} more` }}
    </button>
  </li>
</template>

<script>
export default {
  name: 'ListMoreToggle',
  props: {
    expanded: {type: Boolean, required: true},
    hidden: {type: Number, required: true},
    preview: {type: Number, required: true}
  },
  emits: ['toggle']
};
</script>

<style>
/* The last row of the list rather than a control floating under it */
.list-more-toggle {
  border-top: 1px solid var(--cavil-border-muted);
}

.list-more-toggle button {
  align-items: center;
  background: transparent;
  border: 0;
  color: var(--cavil-fg-muted);
  cursor: pointer;
  display: flex;
  font-size: 13px;
  font-weight: 600;
  gap: 0.45rem;
  justify-content: center;
  padding: 0.6rem 1rem;
  width: 100%;
}
.list-more-toggle button:hover {
  color: var(--cavil-accent);
}
</style>
