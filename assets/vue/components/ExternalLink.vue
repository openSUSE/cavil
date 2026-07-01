<template>
  <span v-if="hasLabel" class="cavil-external-link">
    <a
      v-if="hasUrl"
      class="cavil-external-link-target"
      :href="link.url"
      target="_blank"
      rel="noopener"
      :title="link.title || 'External link'"
    >
      <span class="cavil-external-link-text">{{ text }}</span>
    </a>
    <span v-else class="cavil-external-link-target">
      <span class="cavil-external-link-text">{{ text }}</span>
    </span>
    <span class="cavil-external-link-source">
      <span class="cavil-external-link-source-text">{{ link.label }}</span>
    </span>
  </span>
  <a
    v-else-if="hasUrl"
    class="cavil-external-link-target"
    :href="link.url"
    target="_blank"
    rel="noopener"
    :title="link.title || 'External link'"
  >
    <span class="cavil-external-link-text">{{ text }}</span>
  </a>
  <span v-else>{{ text }}</span>
</template>

<script>
export default {
  name: 'ExternalLink',
  props: {
    link: {
      type: [Object, String],
      default: null
    }
  },
  computed: {
    text() {
      if (this.link && typeof this.link === 'object') return this.link.text ?? '';
      return this.link ?? '';
    },
    hasLabel() {
      return this.link && typeof this.link === 'object' && !!this.link.label;
    },
    hasUrl() {
      return this.link && typeof this.link === 'object' && !!this.link.url;
    }
  }
};
</script>
