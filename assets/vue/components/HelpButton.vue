<template>
  <button type="button" class="cavil-notice-help-button" :aria-label="`Help: ${label}`" title="What is this?">
    <i class="fa-regular fa-circle-question" aria-hidden="true"></i>
  </button>
</template>

<script>
export default {
  name: 'HelpButton',
  props: {label: {type: String, required: true}}
};
</script>
