<template>
  <span
    class="cavil-copyable"
    :class="{copied}"
    tabindex="0"
    role="button"
    :title="title"
    :aria-label="ariaLabel || title"
    @click.prevent="copy"
    @keydown.enter.prevent="copy"
    @keydown.space.prevent="copy"
  >
    <slot>{{ value }}</slot>
  </span>
</template>

<script>
export default {
  name: 'CopyableText',
  props: {
    value: {type: String, required: true},
    title: {type: String, default: 'Click to copy'},
    ariaLabel: {type: String, default: null}
  },
  data() {
    return {copied: false};
  },
  methods: {
    async copy() {
      try {
        await navigator.clipboard.writeText(this.value);
      } catch (err) {
        console.error('Copy to clipboard failed:', err);
        return;
      }
      this.copied = true;
      setTimeout(() => {
        this.copied = false;
      }, 2000);
    }
  }
};
</script>

<style>
.cavil-copyable {
  cursor: pointer;
  display: inline-block;
}
.cavil-copyable.copied::after {
  color: #1a7f37;
  content: ' Copied!';
  font-weight: 500;
  margin-left: 0.5rem;
}
</style>
