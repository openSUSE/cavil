<template>
  <div class="toaster-container" aria-live="polite" aria-atomic="true">
    <transition-group name="toast" tag="div">
      <div v-for="toast in toasts" :key="toast.id" :class="['toast-item', `toast-${toast.variant}`]" role="status">
        <i v-if="toast.variant === 'success'" class="fa-solid fa-circle-check toast-icon"></i>
        <i v-else-if="toast.variant === 'danger'" class="fa-solid fa-circle-xmark toast-icon"></i>
        <i v-else class="fa-solid fa-circle-info toast-icon"></i>
        <span class="toast-message">{{ toast.message }}</span>
      </div>
    </transition-group>
  </div>
</template>

<script>
let nextId = 1;

export default {
  name: 'ToastNotifier',
  data() {
    return {toasts: []};
  },
  methods: {
    notify(message, variant = 'success', duration = 3000) {
      const id = nextId++;
      this.toasts.push({id, message, variant});
      setTimeout(() => {
        const i = this.toasts.findIndex(t => t.id === id);
        if (i !== -1) this.toasts.splice(i, 1);
      }, duration);
    }
  }
};
</script>

<style scoped>
.toaster-container {
  position: fixed;
  bottom: 1.25rem;
  right: 1.25rem;
  z-index: 1080;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  pointer-events: none;
}
.toast-item {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  min-width: 240px;
  max-width: 360px;
  padding: 0.65rem 0.9rem;
  border-radius: 0.5rem;
  background: #ffffff;
  color: #1f2328;
  font-size: 14px;
  line-height: 1.3;
  box-shadow:
    0 6px 24px rgba(31, 35, 40, 0.18),
    0 2px 6px rgba(31, 35, 40, 0.08);
  border-left: 4px solid #6c757d;
  pointer-events: auto;
}
.toast-success {
  border-left-color: #1a7f37;
}
.toast-success .toast-icon {
  color: #1a7f37;
}
.toast-danger {
  border-left-color: #cf222e;
}
.toast-danger .toast-icon {
  color: #cf222e;
}
.toast-info .toast-icon {
  color: #0969da;
}
.toast-icon {
  font-size: 16px;
}
.toast-message {
  flex: 1;
}
.toast-enter-active,
.toast-leave-active {
  transition:
    opacity 0.25s ease,
    transform 0.25s ease;
}
.toast-enter-from {
  opacity: 0;
  transform: translateX(20px);
}
.toast-leave-to {
  opacity: 0;
  transform: translateX(20px);
}
.toast-move {
  transition: transform 0.25s ease;
}
</style>
