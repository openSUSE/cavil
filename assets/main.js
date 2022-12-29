import './sass/app.scss';
import 'bootstrap/dist/css/bootstrap.css';
import 'datatables.net-bs4/css/dataTables.bootstrap4.css';
import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/neo.css';

import 'timeago';
import 'bootstrap';
import 'datatables.net';
import 'datatables.net-bs4';
import 'codemirror';
import 'moment';

import {setupCodeMirrorForFile} from './legacy/file.js';
import {backToTop} from './legacy/nav.js';
import {setupCreatePattern} from './legacy/patterns.js';
import {setupProductTable} from './legacy/product.js';
import {setupReviewDetails} from './legacy/review.js';
import {setupCodeMirrorForSnippet} from './legacy/snippet.js';
import {fromNow} from './legacy/time.js';
import {createLicense, ignoreLine, snippetNonLicense, snippetSwitcher} from './legacy/util.js';
import KnownLicenses from './vue/KnownLicenses.vue';
import OpenReviews from './vue/OpenReviews.vue';
import RecentReviews from './vue/RecentReviews.vue';
import ReviewSearch from './vue/ReviewSearch.vue';
import $ from 'jquery';
import {createApp} from 'vue';

window.$ = $;
window.jQuery = $;

window.cavil = {
  fireIndex: undefined,
  fires: undefined,
  myCodeMirror: undefined,

  setupKnownLicenses() {
    createApp(KnownLicenses).mount('#known-licenses');
  },

  setupOpenReviews() {
    createApp(OpenReviews).mount('#open-reviews');
  },

  setupRecentReviews() {
    createApp(RecentReviews).mount('#recent-reviews');
  },

  setupReviewSearch(pkg) {
    const app = createApp(ReviewSearch);
    app.config.globalProperties.currentPackage = pkg;
    app.mount('#review-search');
  },

  backToTop,
  createLicense,
  fromNow,
  ignoreLine,
  setupCodeMirrorForFile,
  setupCodeMirrorForSnippet,
  setupCreatePattern,
  setupProductTable,
  setupReviewDetails,
  snippetNonLicense,
  snippetSwitcher
};
