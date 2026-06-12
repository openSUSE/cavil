<template>
  <section :id="id" :class="panelClasses">
    <div v-if="title !== null" class="cavil-notice-heading">
      <i v-if="icon !== null" :class="icon"></i>
      {{ title }}
    </div>
    <slot>
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
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 8px;
  color: #1f2328;
  margin: 1.25rem 0;
  overflow: hidden;
}
.cavil-notice-panel-intro {
  align-items: center;
  background: #f6f8fa;
  color: #57606a;
  display: flex;
  flex-wrap: wrap;
  font-size: 14px;
  gap: 0.75rem;
  line-height: 1.45;
  margin: 0 0 1rem;
  padding: 0.75rem 0.9rem;
}
.cavil-notice-panel-intro .btn {
  margin-left: auto;
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
  background: #f6f8fa;
  border-bottom: 1px solid #d0d7de;
  color: #1f2328;
  display: flex;
  font-size: 13px;
  font-weight: 700;
  gap: 0.45rem;
  line-height: 1.35;
  padding: 0.65rem 0.85rem;
}
.cavil-notice-heading i {
  color: #6e7781;
}
.cavil-notice-panel-warning {
  border-color: #eac54f;
}
.cavil-notice-panel-warning .cavil-notice-heading {
  background: #fff8c5;
  border-bottom-color: #eac54f;
  color: #7d4e00;
}
.cavil-notice-panel-warning .cavil-notice-heading i {
  color: #7d4e00;
}
.cavil-notice-panel-info {
  border-color: #b6e3ff;
}
.cavil-notice-panel-info .cavil-notice-heading {
  background: #ddf4ff;
  border-bottom-color: #b6e3ff;
  color: #0550ae;
}
.cavil-notice-panel-info .cavil-notice-heading i {
  color: #0550ae;
}
.cavil-notice-panel-success .cavil-notice-heading i {
  color: #1a7f37;
}
.cavil-notice-list {
  list-style: none;
  margin: 0;
  padding: 0;
}
.cavil-notice-summary {
  background: #ffffff;
  color: #57606a;
  font-size: 13px;
  line-height: 1.45;
  margin: 0;
  padding: 0.75rem 0.85rem;
}
.cavil-notice-summary + .cavil-notice-list {
  border-top: 1px solid #d8dee4;
}
.cavil-notice-item {
  background: #ffffff;
  color: #1f2328;
  font-size: 13px;
  line-height: 1.45;
  overflow-wrap: anywhere;
  padding: 0.75rem 0.85rem;
}
.cavil-notice-panel-warning .cavil-notice-item {
  padding-left: 2rem;
  position: relative;
}
.cavil-notice-panel-warning .cavil-notice-item::before {
  background: #bf8700;
  border-radius: 50%;
  content: '';
  height: 0.4rem;
  left: 0.9rem;
  position: absolute;
  top: 1.25rem;
  width: 0.4rem;
}
.cavil-notice-item + .cavil-notice-item {
  border-top: 1px solid #d8dee4;
}
.cavil-notice-pre {
  background: #ffffff;
  color: #1f2328;
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
  color: #57606a;
  font-weight: 600;
}
.cavil-notice-definition-list dd {
  color: #1f2328;
  margin: 0;
  min-width: 0;
  overflow-wrap: anywhere;
}
@media (max-width: 575.98px) {
  .cavil-notice-panel-intro {
    align-items: flex-start;
    flex-direction: column;
  }
  .cavil-notice-panel-intro .btn {
    margin-left: 0;
  }
}
</style>
