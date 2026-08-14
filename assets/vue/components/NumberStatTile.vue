<template>
  <article class="stats-number-tile">
    <div class="stats-tile-label">{{ label }}</div>
    <div class="stats-tile-value">{{ value.toLocaleString() }}</div>
  </article>
</template>

<script>
export default {
  name: 'NumberStatTile',
  props: {
    label: {type: String, required: true},
    value: {type: Number, required: true}
  }
};
</script>

<style scoped>
.stats-number-tile {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  box-shadow: 0 1px 2px rgba(var(--cavil-shadow-rgb), 0.04);
  color: var(--cavil-fg-emphasis);
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  justify-content: space-between;
  min-height: 122px;
  min-width: 0;
  padding: 1rem;
}

.stats-tile-label {
  color: var(--cavil-fg-muted);
  font-size: 0.78rem;
  font-weight: 600;
  letter-spacing: 0;
  text-transform: uppercase;
}

.stats-tile-value {
  color: var(--cavil-fg-emphasis);
  font-size: 2rem;
  font-weight: 600;
  line-height: 1;
}
</style>
