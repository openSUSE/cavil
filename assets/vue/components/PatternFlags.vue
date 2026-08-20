<template>
  <div class="pattern-flags">
    <div class="form-check" v-for="flag in flags" :key="flag.name">
      <input
        :checked="modelValue[flag.name]"
        @change="set(flag.name, $event.target.checked)"
        type="checkbox"
        class="form-check-input"
        :id="flag.name"
        :name="flag.name"
        value="1"
      />
      <label class="form-check-label" :for="flag.name">{{ flag.label }}</label>
    </div>
  </div>
</template>

<script>
// The legal properties a curator sets on a pattern, in one place so the pattern editor and the inline
// session the file viewer opens cannot drift apart about which exist. Mirrors @PATTERN_FLAGS in
// Cavil::Util, which the server validates and stores from.
export const LICENSE_FLAGS = [
  {name: 'patent', label: 'Patent'},
  {name: 'trademark', label: 'Trademark'},
  {name: 'cla', label: 'CLA'},
  {name: 'eula', label: 'EULA'},
  {name: 'export_restricted', label: 'Export Restricted'}
];

// The last one is not a fact about the license like the others, but about this one pattern: its text is
// the license in full, so a NOTICE can reproduce it for a license with no SPDX identifier
export const PATTERN_FLAGS = [...LICENSE_FLAGS, {name: 'full_license_text', label: 'Full license text'}];

export default {
  name: 'PatternFlags',
  props: {
    modelValue: {type: Object, required: true}
  },
  emits: ['update:modelValue'],
  data() {
    return {flags: PATTERN_FLAGS};
  },
  methods: {
    set(name, checked) {
      this.$emit('update:modelValue', {...this.modelValue, [name]: checked});
    }
  }
};
</script>

<style scoped>
.pattern-flags {
  display: flex;
  flex-wrap: wrap;
  gap: 0 1.5rem;
}
</style>
