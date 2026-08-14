<template>
  <section :id="id" :class="panelClasses">
    <div v-if="title !== null" class="cavil-notice-heading">
      <i v-if="icon !== null" :class="icon"></i>
      {{ title }}
      <span v-if="note !== null" class="cavil-notice-heading-note">{{ note }}</span>
    </div>
    <!-- Intro prose needs a box of its own, an anonymous flex item cannot be told to shrink -->
    <template v-if="intro">
      <div class="cavil-notice-panel-intro-text"><slot></slot></div>
      <div v-if="$slots.actions" class="cavil-notice-panel-intro-actions"><slot name="actions"></slot></div>
    </template>
    <slot v-else>
      <ul class="cavil-notice-list">
        <li v-for="item in items" :key="item" class="cavil-notice-item">{{ item }}</li>
      </ul>
    </slot>
  </section>
</template>

<script>
export default {
  name: 'CavilNoticePanel',
  props: {
    icon: {type: String, default: null},
    id: {type: String, default: null},
    intro: {type: Boolean, default: false},
    items: {type: Array, default: () => []},
    note: {type: String, default: null},
    title: {type: String, default: null},
    tone: {type: String, default: 'neutral'}
  },
  computed: {
    panelClasses() {
      return [
        'cavil-notice-panel',
        `cavil-notice-panel-${this.tone}`,
        {'cavil-notice-panel-intro': this.intro, 'cavil-notice-panel-with-heading': this.title !== null}
      ];
    }
  }
};
</script>

<style>
.cavil-notice-panel {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 8px;
  color: var(--cavil-fg);
  margin: 1.25rem 0;
  overflow: hidden;
}
.cavil-notice-panel-intro {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  color: var(--cavil-fg-muted);
  display: flex;
  font-size: 14px;
  gap: 0.75rem;
  line-height: 1.45;
  margin: 0 0 1rem;
  padding: 0.75rem 0.9rem;
}
.cavil-notice-panel-intro-text {
  flex: 1 1 auto;
  min-width: 0;
}
.cavil-notice-panel-intro-actions {
  align-items: center;
  display: flex;
  flex: 0 0 auto;
  gap: 0.5rem;
}
.cavil-notice-panel-intro .btn {
  white-space: nowrap;
}
.cavil-notice-panel-intro a:not(.btn) {
  font-weight: 600;
  text-decoration-color: transparent;
}
.cavil-notice-panel-intro a:not(.btn):hover,
.cavil-notice-panel-intro a:not(.btn):focus {
  text-decoration-color: currentColor;
}
.cavil-notice-heading {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border-bottom: 1px solid var(--cavil-border);
  color: var(--cavil-fg);
  display: flex;
  font-size: 13px;
  font-weight: 600;
  gap: 0.45rem;
  line-height: 1.35;
  padding: 0.65rem 0.85rem;
}
.cavil-notice-heading i {
  color: var(--cavil-fg-subtle);
}
/* What the panel is not showing belongs to the panel, not to a row of the list it is missing from */
.cavil-notice-heading-note {
  color: var(--cavil-fg-subtle);
  font-weight: 400;
  margin-left: auto;
}
.cavil-notice-panel-warning {
  border-color: var(--cavil-attention-3);
}
.cavil-notice-panel-warning .cavil-notice-heading {
  background: var(--cavil-attention-bg);
  border-bottom-color: var(--cavil-attention-3);
  color: var(--cavil-attention-deep);
}
.cavil-notice-panel-warning .cavil-notice-heading i {
  color: var(--cavil-attention-deep);
}
.cavil-notice-panel-info {
  border-color: var(--cavil-accent-border);
}
.cavil-notice-panel-info .cavil-notice-heading {
  background: var(--cavil-accent-bg);
  border-bottom-color: var(--cavil-accent-border);
  color: var(--cavil-accent-strong);
}
.cavil-notice-panel-info .cavil-notice-heading i {
  color: var(--cavil-accent-strong);
}
.cavil-notice-panel-success {
  border-color: var(--cavil-success-tint-3);
}
.cavil-notice-panel-success .cavil-notice-heading {
  background: var(--cavil-success-tint-1);
  border-bottom-color: var(--cavil-success-tint-3);
  color: var(--cavil-success-deep);
}
.cavil-notice-panel-success .cavil-notice-heading i {
  color: var(--cavil-success-deep);
}
/* Light edges these panels with a pale tint of the hue. Inverting a pale tint lands on a
   saturated mid-tone, which next to the chips reads as a hard outline, so dark uses the
   same translucent hue border the chips do. The heading only has a bottom edge, so setting
   all four is harmless. */
[data-bs-theme='dark'] .cavil-notice-panel-warning,
[data-bs-theme='dark'] .cavil-notice-panel-warning .cavil-notice-heading {
  border-color: var(--cavil-attention-border);
}
[data-bs-theme='dark'] .cavil-notice-panel-success,
[data-bs-theme='dark'] .cavil-notice-panel-success .cavil-notice-heading {
  border-color: var(--cavil-success-border);
}

.cavil-notice-list {
  list-style: none;
  margin: 0;
  padding: 0;
}
.cavil-notice-summary {
  background: var(--cavil-canvas);
  color: var(--cavil-fg-muted);
  font-size: 13px;
  line-height: 1.45;
  margin: 0;
  padding: 0.75rem 0.85rem;
}
.cavil-notice-summary + .cavil-notice-list {
  border-top: 1px solid var(--cavil-border-muted);
}
.cavil-notice-item {
  background: var(--cavil-canvas);
  color: var(--cavil-fg);
  font-size: 14px;
  line-height: 1.45;
  overflow-wrap: anywhere;
  padding: 0.75rem 0.85rem;
  white-space: pre-wrap;
}
.cavil-notice-panel-warning .cavil-notice-item {
  padding-left: 2rem;
  position: relative;
}
.cavil-notice-panel-warning .cavil-notice-item::before {
  background: var(--cavil-attention-strong);
  border-radius: 50%;
  content: '';
  height: 0.4rem;
  left: 0.9rem;
  position: absolute;
  top: 1.25rem;
  width: 0.4rem;
}
.cavil-notice-item + .cavil-notice-item {
  border-top: 1px solid var(--cavil-border-muted);
}
.cavil-notice-pre {
  background: var(--cavil-canvas);
  color: var(--cavil-fg);
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 12px;
  line-height: 1.5;
  margin: 0;
  overflow-x: auto;
  padding: 0.75rem 0.85rem;
  white-space: pre-wrap;
}
.cavil-notice-definition-list {
  display: grid;
  font-size: 13px;
  gap: 0.35rem 0.85rem;
  grid-template-columns: max-content minmax(0, 1fr);
  margin: 0;
  padding: 0.75rem 0.85rem;
}
.cavil-notice-definition-list dt {
  color: var(--cavil-fg-muted);
  font-weight: 600;
}
.cavil-notice-definition-list dd {
  color: var(--cavil-fg);
  margin: 0;
  min-width: 0;
  overflow-wrap: anywhere;
}
@media (max-width: 575.98px) {
  .cavil-notice-panel-intro {
    align-items: flex-start;
    flex-direction: column;
  }
}
</style>
