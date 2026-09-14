<template>
  <span v-if="cves.length > 0" class="badge cavil-cve-badge" :title="title">CVE</span>
</template>

<script>
export default {
  name: 'CveBadge',
  props: {
    tags: {
      type: Array,
      default: () => []
    }
  },
  computed: {
    cves() {
      return (this.tags ?? []).filter(tag => /^CVE(-|$)/i.test(tag));
    },
    title() {
      const what = this.cves.length === 1 ? 'a security issue' : `${this.cves.length} security issues`;
      return `Fixes ${what}: ${this.cves.join(', ')}`;
    }
  }
};
</script>
