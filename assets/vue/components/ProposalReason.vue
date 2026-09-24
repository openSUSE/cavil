<template>
  <div class="proposal-reason markdown-body" v-html="html"></div>
</template>

<script>
// Server-rendered, sanitised markdown reason of a proposed change (same pipeline as notes)
export default {
  name: 'ProposalReason',
  props: {html: {type: String, required: true}}
};
</script>

<style scoped>
.proposal-reason {
  background: var(--cavil-canvas);
  color: var(--cavil-fg);
  font-size: 14px;
  line-height: 1.5;
}
.proposal-reason :deep(h1),
.proposal-reason :deep(h2),
.proposal-reason :deep(h3),
.proposal-reason :deep(h4) {
  font-size: 15px;
  font-weight: 600;
  margin: 16px 0 8px;
}
.proposal-reason :deep(h1:first-child),
.proposal-reason :deep(h2:first-child),
.proposal-reason :deep(h3:first-child) {
  margin-top: 0;
}
.proposal-reason :deep(p) {
  margin-bottom: 12px;
}
.proposal-reason :deep(p:last-child) {
  margin-bottom: 0;
}
.proposal-reason :deep(ul),
.proposal-reason :deep(ol) {
  margin-bottom: 12px;
  padding-left: 22px;
}
.proposal-reason :deep(li + li) {
  margin-top: 4px;
}
.proposal-reason :deep(code) {
  background: rgba(var(--cavil-neutral-cool-rgb), 0.2);
  border-radius: 4px;
  font-size: 85%;
  padding: 0.2em 0.4em;
}
.proposal-reason :deep(pre) {
  background: var(--cavil-canvas-subtle);
  border-radius: 6px;
  font-size: 12px;
  overflow: auto;
  padding: 12px;
}
.proposal-reason :deep(pre code) {
  background: transparent;
  padding: 0;
}
.proposal-reason :deep(a) {
  color: var(--cavil-accent);
}
</style>
