<template>
  <div class="empty-state">
    <i :class="['fa-solid', icon, 'empty-state-icon']"></i>
    <h3 class="empty-state-title">{{ title }}</h3>
    <p class="empty-state-text">
      <slot>{{ message }}</slot>
    </p>
  </div>
</template>

<script>
// Friendly "inbox zero" placeholder for empty review queues - an empty list is a good thing, so
// celebrate it instead of stating a bland absence.
export default {
  name: 'EmptyState',
  props: {
    title: {type: String, default: 'All caught up!'},
    message: {type: String, default: ''},
    icon: {type: String, default: 'fa-circle-check'}
  }
};
</script>

<style scoped>
.empty-state {
  align-items: center;
  color: #57606a;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  padding: 3.5rem 1rem;
  text-align: center;
}
.empty-state-icon {
  color: #1a7f37;
  font-size: 2.5rem;
}
.empty-state-title {
  color: #1f2328;
  font-size: 1.1rem;
  font-weight: 600;
  margin: 0.5rem 0 0;
}
.empty-state-text {
  margin: 0;
  max-width: 28rem;
}
</style>
