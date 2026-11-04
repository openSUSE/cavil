<template>
  <span class="cavil-package-name"
    ><span
      v-for="(segment, i) in segments"
      :key="i"
      :class="{'cavil-package-name-folded': segment.folded}"
      :title="segment.folded ? foldedTitle : null"
      >{{ segment.text }}</span
    ></span
  >
</template>

<script>
// The family only ever drops characters from the name, so walking both once marks what was folded away
export default {
  name: 'PackageName',
  props: {
    family: {type: String, default: null},
    name: {type: String, required: true}
  },
  computed: {
    foldedTitle() {
      return `Version suffix, decisions and notes are shared across the ${this.family} package family`;
    },
    segments() {
      const {family, name} = this;
      if (family === null || family === name) return [{text: name, folded: false}];

      const segments = [];
      let matched = 0;
      for (const char of name) {
        const folded = char !== family[matched];
        if (!folded) matched++;
        const last = segments[segments.length - 1];
        if (last !== undefined && last.folded === folded) last.text += char;
        else segments.push({text: char, folded});
      }
      return matched === family.length ? segments : [{text: name, folded: false}];
    }
  }
};
</script>

<style>
.cavil-package-name-folded {
  color: var(--cavil-fg-muted);
}
</style>
