<template>
  <span v-if="hasContext" class="cavil-external-link">
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
    <span v-if="hasLabel" class="cavil-external-link-source">
      <span class="cavil-external-link-source-text">{{ link.label }}</span>
    </span>
    <details v-if="hasTarget" class="cavil-external-link-submission" :title="`Submission target: ${link.target}`">
      <summary class="cavil-external-link-submission-summary">
        <span class="cavil-external-link-submission-prefix">to</span>
        <span class="cavil-external-link-submission-text">
          <span class="cavil-external-link-target-project">{{ targetProject }}</span>
          <span v-if="targetPackage" class="cavil-external-link-target-package">/{{ targetPackage }}</span>
        </span>
      </summary>
    </details>
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
    hasTarget() {
      return this.link && typeof this.link === 'object' && !!this.link.target;
    },
    targetProject() {
      if (!this.hasTarget) return '';
      const separator = this.link.target.lastIndexOf('/');
      return separator > 0 ? this.link.target.slice(0, separator) : this.link.target;
    },
    targetPackage() {
      if (!this.hasTarget) return '';
      const separator = this.link.target.lastIndexOf('/');
      return separator > 0 ? this.link.target.slice(separator + 1) : '';
    },
    hasContext() {
      return this.hasLabel || this.hasTarget;
    },
    hasUrl() {
      return this.link && typeof this.link === 'object' && !!this.link.url;
    }
  }
};
</script>
