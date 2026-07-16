<template>
  <div :class="['legal-loading', `legal-loading-${size}`]" role="status" aria-live="polite">
    <div class="legal-loading-mark" aria-hidden="true">
      <span class="legal-loading-icon-shell">
        <i :class="icon"></i>
        <span class="legal-loading-pulse"></span>
      </span>
    </div>
    <span class="legal-loading-text">{{ message }}</span>
  </div>
</template>

<script>
export default {
  name: 'LegalLoading',
  props: {
    icon: {type: String, default: 'fa-solid fa-scale-balanced'},
    message: {type: String, default: 'Loading case files...'},
    size: {type: String, default: 'regular'}
  }
};
</script>

<style scoped>
.legal-loading {
  --legal-loading-accent: #2f6f5e;
  --legal-loading-ink: #24292f;
  --legal-loading-surface: #f6f8fa;

  align-items: center;
  color: #57606a;
  display: inline-flex;
  gap: 0.75rem;
  justify-content: center;
  min-height: 3.25rem;
}
.legal-loading-full {
  display: flex;
  padding: 2rem 1rem;
  width: 100%;
}
.legal-loading-small {
  gap: 0.5rem;
  min-height: 1.75rem;
}
.legal-loading-mark {
  display: grid;
  flex: 0 0 auto;
  height: 2.75rem;
  place-items: center;
  width: 2.75rem;
}
.legal-loading-small .legal-loading-mark {
  height: 2.1rem;
  width: 2.1rem;
}
.legal-loading-icon-shell {
  align-items: center;
  animation: legal-loading-weigh 1.55s ease-in-out infinite;
  background: var(--legal-loading-surface);
  border: 1px solid rgba(110, 119, 129, 0.22);
  border-radius: 0.65rem;
  box-sizing: border-box;
  box-shadow: 0 0.35rem 0.8rem rgba(36, 41, 47, 0.1);
  color: var(--legal-loading-accent);
  display: grid;
  font-size: 1.35rem;
  height: 2.5rem;
  overflow: hidden;
  place-items: center;
  position: relative;
  transform-origin: 50% 70%;
  width: 2.5rem;
}
.legal-loading-icon-shell i {
  display: inline-block;
  line-height: 1;
  position: relative;
  text-align: center;
  width: var(--fa-width, 1.25em);
  z-index: 1;
}
.legal-loading-icon-shell i.fa-scale-balanced,
.legal-loading-icon-shell i.fa-balance-scale {
  --fa-width: 1.35em;

  transform: translateX(0.06em);
}
.legal-loading-pulse {
  animation: legal-loading-pulse 1.55s ease-in-out infinite;
  background: rgba(47, 111, 94, 0.12);
  border-radius: 999px;
  height: 1.8rem;
  position: absolute;
  width: 1.8rem;
}
.legal-loading-text {
  color: #57606a;
  font-size: 0.95rem;
  font-weight: 500;
}
.legal-loading-full .legal-loading-text {
  color: #424a53;
  font-size: 1rem;
}
.legal-loading-small .legal-loading-text {
  font-size: 0.9rem;
}
.legal-loading-small .legal-loading-icon-shell {
  font-size: 1rem;
  height: 2rem;
  width: 2rem;
}
.legal-loading-small .legal-loading-pulse {
  height: 1.35rem;
  width: 1.35rem;
}

@keyframes legal-loading-weigh {
  0%,
  100% {
    transform: rotate(-4deg);
  }
  50% {
    transform: rotate(4deg);
  }
}
@keyframes legal-loading-pulse {
  0%,
  100% {
    opacity: 0.28;
    transform: scale(0.62);
  }
  50% {
    opacity: 0.9;
    transform: scale(1.18);
  }
}

@media (prefers-reduced-motion: reduce) {
  .legal-loading-icon-shell,
  .legal-loading-pulse {
    animation: none;
  }
}
</style>
