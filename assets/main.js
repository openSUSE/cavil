import './sass/app.scss';
import 'bootstrap/dist/css/bootstrap.css';
import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/neo.css';

import 'timeago';
import 'bootstrap';
import 'codemirror';
import 'moment';

import {setupCodeMirrorForFile} from './legacy/file.js';
import {setupReviewDetails} from './legacy/review.js';
import {setupCodeMirrorForSnippet} from './legacy/snippet.js';
import {fromNow} from './legacy/time.js';
import {createLicense, ignoreLine, snippetNonLicense} from './legacy/util.js';
import ClassifySnippets from './vue/ClassifySnippets.vue';
import EditSnippet from './vue/EditSnippet.vue';
import KnownLicenses from './vue/KnownLicenses.vue';
import KnownProducts from './vue/KnownProducts.vue';
import OpenReviews from './vue/OpenReviews.vue';
import ProductReviews from './vue/ProductReviews.vue';
import RecentReviews from './vue/RecentReviews.vue';
import ReportMetadata from './vue/ReportMetadata.vue';
import ReviewSearch from './vue/ReviewSearch.vue';
import $ from 'jquery';
import {createApp} from 'vue';

window.$ = $;
window.jQuery = $;

window.cavil = {
  fireIndex: undefined,
  fires: undefined,
  myCodeMirror: undefined,

  setupClassifySnippets(hasClassifierRole) {
    const app = createApp(ClassifySnippets);
    app.config.globalProperties.hasClassifierRole = hasClassifierRole;
    app.mount('#classify-snippets');
  },

  setupEditSnippet(snippet) {
    const app = createApp(EditSnippet);
    app.config.globalProperties.currentSnippet = snippet;
    app.mount('#edit-snippet');
  },

  setupKnownLicenses() {
    createApp(KnownLicenses).mount('#known-licenses');
  },

  setupKnownProducts() {
    createApp(KnownProducts).mount('#known-products');
  },

  setupOpenReviews() {
    createApp(OpenReviews).mount('#open-reviews');
  },

  setupProductReviews(product) {
    const app = createApp(ProductReviews);
    app.config.globalProperties.currentProduct = product;
    app.mount('#product-reviews');
  },

  setupRecentReviews() {
    createApp(RecentReviews).mount('#recent-reviews');
  },

  setupReportMetadata(pkgId, hasManagerRole, hasAdminRole) {
    const app = createApp(ReportMetadata);
    app.config.globalProperties.pkgId = pkgId;
    app.config.globalProperties.hasManagerRole = hasManagerRole;
    app.config.globalProperties.hasAdminRole = hasAdminRole;
    app.mount('#report-metadata');
  },

  setupReviewSearch(pkg) {
    const app = createApp(ReviewSearch);
    app.config.globalProperties.currentPackage = pkg;
    app.mount('#review-search');
  },

  createLicense,
  fromNow,
  ignoreLine,
  setupCodeMirrorForFile,
  setupCodeMirrorForSnippet,
  setupReviewDetails,
  snippetNonLicense
};
