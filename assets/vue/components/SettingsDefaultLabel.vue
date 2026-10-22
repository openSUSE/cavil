<template>
  <button
    v-if="custom.includes(name)"
    type="button"
    class="cavil-settings-reset"
    :data-reset="name"
    @click="$emit('reset', name)"
  >
    Reset to default
  </button>
  <span v-else class="cavil-settings-default" :data-default="name">Default</span>
</template>

<script>
export default {
  name: 'SettingsDefaultLabel',
  props: {
    custom: {type: Array, required: true},
    name: {type: String, required: true}
  },
  emits: ['reset']
};
</script>
