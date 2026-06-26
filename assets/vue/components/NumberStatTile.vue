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
  background: #fff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 1px 2px rgba(27, 31, 36, 0.04);
  color: #24292f;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  justify-content: space-between;
  min-height: 122px;
  min-width: 0;
  padding: 1rem;
}

.stats-tile-label {
  color: #57606a;
  font-size: 0.78rem;
  font-weight: 600;
  letter-spacing: 0;
  text-transform: uppercase;
}

.stats-tile-value {
  color: #24292f;
  font-size: 2rem;
  font-weight: 600;
  line-height: 1;
}
</style>
