<template>
  <div class="cavil-segmented" role="group" :aria-label="label">
    <button
      v-for="option in options"
      :key="option.value"
      type="button"
      class="cavil-segmented-btn"
      :class="{'is-on': modelValue === option.value}"
      :aria-pressed="modelValue === option.value ? 'true' : 'false'"
      :title="option.title"
      v-bind="option.attrs"
      @click="$emit('update:modelValue', option.value)"
    >
      {{ option.label }}
    </button>
  </div>
</template>

<script>
export default {
  name: 'SegmentedControl',
  props: {
    label: {type: String, required: true},
    modelValue: {type: String, required: true},
    options: {type: Array, required: true}
  },
  emits: ['update:modelValue']
};
</script>

<style>
.cavil-segmented {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  display: inline-flex;
  overflow: hidden;
}
.cavil-segmented-btn {
  appearance: none;
  background: var(--cavil-canvas);
  border: 0;
  color: var(--cavil-fg-muted);
  cursor: pointer;
  font: inherit;
  font-size: 12px;
  font-weight: 600;
  line-height: 1.2;
  padding: 0.25rem 0.6rem;
}
.cavil-segmented-btn + .cavil-segmented-btn {
  border-left: 1px solid var(--cavil-border);
}
.cavil-segmented-btn:hover {
  background: var(--cavil-canvas-subtle);
}
.cavil-segmented-btn.is-on {
  background: var(--cavil-accent-emphasis);
  color: var(--cavil-on-accent);
}
</style>
