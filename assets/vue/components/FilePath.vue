<template>
  <span class="cavil-path"
    ><span v-if="directory" class="cavil-path-dir">{{ directory }}</span
    >{{ basename }}</span
  >
</template>

<script>
// A file path with its directory a step quieter than its name. Paths in a report run long - a TeX Live
// licence sits at "arara/texmf-dist/scripts/arara/arara/META-INF/LICENSE" - and the one word being looked
// for is always the last, at a different offset on every row. Nothing is shortened or hidden: the
// directory genuinely matters, it is just mostly repetition wrapped around the name, and every file in a
// package shares the version directory so that prefix recedes for free.
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
/* Colour alone does the dimming. Lightening the colour *and* thinning the weight made the directory look
   blurred rather than quiet, and dimming by only one step (#6e7781) left it indistinguishable from the
   file name at #57606a - so it is the subtle grey at the name's own weight. */
.cavil-path-dir {
  color: #8c959f;
}
/* Inside a link the whole path lights up together on hover, so the dimming never makes half of it look
   unclickable. Only ever matches an element that opted in by carrying the class. */
a:hover > .cavil-path > .cavil-path-dir,
a:focus > .cavil-path > .cavil-path-dir {
  color: inherit;
}
</style>
