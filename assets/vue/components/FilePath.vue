<template>
  <span class="cavil-path"
    ><span v-if="directory" class="cavil-path-dir">{{ directory }}</span
    ><span class="cavil-path-name">{{ basename }}</span></span
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
    basename() {
      return this.path.slice(this.path.lastIndexOf('/') + 1);
    }
  }
};
</script>

<style>
/* Contrast comes from the near-black name, not from fading the directory. At #8c959f the directory reads
   as washed out, and a lower font-weight blurs it; both were checked against production paths. */
.cavil-path-dir {
  color: #6e7781;
}
.cavil-path-name {
  color: #24292f;
}
/* Both halves follow the link colour on hover, so neither looks unclickable. */
a:hover > .cavil-path > *,
a:focus > .cavil-path > * {
  color: inherit;
}
</style>
