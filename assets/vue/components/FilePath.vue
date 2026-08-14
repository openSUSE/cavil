<template>
  <span class="cavil-path" :title="processed ? path : null"
    ><span v-if="directory" class="cavil-path-dir">{{ directory }}</span
    ><span class="cavil-path-name">{{ name }}</span></span
  >
</template>

<script>
// A file path with its directory quieter than its name. Report paths run long
// ("arara/texmf-dist/scripts/arara/arara/META-INF/LICENSE") and the name is always last, so it lands at a
// different offset on every row. Nothing is shortened: directories are worth reading, they are just
// repetitive, and the version directory every file shares recedes for free.
export default {
  name: 'FilePath',
  props: {
    path: {type: String, required: true}
  },
  computed: {
    directory() {
      const cut = this.path.lastIndexOf('/');
      return cut < 0 ? '' : this.path.slice(0, cut + 1);
    },
    // ".processed" is Cavil's marker for its own normalised copy of a file, not part of the upstream
    // name, and file lists only ever show that copy - the original never reaches them, so the marker
    // never distinguishes two rows. Dropping it saves every reader mentally stripping it to recover the
    // name they know; the real path stays in the title, and the file browser shows filenames as they are.
    name() {
      const base = this.path.slice(this.path.lastIndexOf('/') + 1);
      const match = base.match(/^(.*)\.processed(\..*)?$/);
      return match ? match[1] + (match[2] ?? '') : base;
    },
    processed() {
      return /\.processed(\.|$)/.test(this.path);
    }
  }
};
</script>

<style>
/* Contrast comes from the near-black name, not from fading the directory. At var(--cavil-fg-disabled) the directory reads
   as washed out, and a lower font-weight blurs it; both were checked against production paths. */
.cavil-path-dir {
  color: var(--cavil-fg-subtle);
}
.cavil-path-name {
  color: var(--cavil-fg-emphasis);
}
/* Both parts follow the link colour on hover, so neither looks unclickable. */
a:hover .cavil-path *,
a:focus .cavil-path * {
  color: inherit;
}
</style>
