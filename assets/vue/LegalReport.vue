<template>
  <div>
    <report-metadata />
    <report-details ref="details" />
  </div>
</template>

<script>
import ReportDetails from './components/ReportDetails.vue';
import ReportMetadata from './components/ReportMetadata.vue';

// Root of the report page. The metadata and details areas used to be two
// separately mounted Vue apps; they are now sibling components under this one.
// That lets the "why this needs review" box (in ReportMetadata) turn the file
// names in the stored notice into links that drive the same file-preview
// navigation as the Risk 9 section (in ReportDetails), without a cross-component
// event bridge or a per-request diff recompute on the backend.
//
// fileIndex is a shared reactive path => file id map that ReportDetails fills
// from its report data; ReportMetadata reads it to linkify notice lines and
// gotoFile forwards a click to ReportDetails.onFileLinkClick.
export default {
  name: 'LegalReport',
  components: {ReportDetails, ReportMetadata},
  data() {
    return {fileIndex: {}};
  },
  provide() {
    return {
      fileIndex: this.fileIndex,
      gotoFile: id => {
        const details = this.$refs.details;
        if (details) details.onFileLinkClick(id);
      }
    };
  }
};
</script>
