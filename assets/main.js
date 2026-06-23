import './sass/app.scss';
import 'bootstrap/dist/css/bootstrap.css';
import 'bootstrap';
import ApiKeys from './vue/ApiKeys.vue';
import CavilMenu from './vue/CavilMenu.vue';
import CavilStatistics from './vue/CavilStatistics.vue';
import ClassifySnippets from './vue/ClassifySnippets.vue';
import EditPattern from './vue/EditPattern.vue';
import EditSnippet from './vue/EditSnippet.vue';
import FileBrowser from './vue/FileBrowser.vue';
import IgnoredFiles from './vue/IgnoredFiles.vue';
import IgnoredMatches from './vue/IgnoredMatches.vue';
import KnownLicenses from './vue/KnownLicenses.vue';
import KnownProducts from './vue/KnownProducts.vue';
import LicenseDetails from './vue/LicenseDetails.vue';
import MissingLicenses from './vue/MissingLicenses.vue';
import OpenReviews from './vue/OpenReviews.vue';
import ProductReviews from './vue/ProductReviews.vue';
import ProposedPatterns from './vue/ProposedPatterns.vue';
import RecentNotes from './vue/RecentNotes.vue';
import RecentPatterns from './vue/RecentPatterns.vue';
import RecentReviews from './vue/RecentReviews.vue';
import ReportDetails from './vue/ReportDetails.vue';
import ReportMetadata from './vue/ReportMetadata.vue';
import ReviewSearch from './vue/ReviewSearch.vue';
import Upload from './vue/Upload.vue';
import moment from 'moment';
import {createApp} from 'vue';

function updateBackToTopVisibility() {
  const visible = window.scrollY > 200;
  document.querySelectorAll('.back-to-top').forEach(el => {
    el.classList.toggle('visible', visible);
  });
}
window.addEventListener('scroll', updateBackToTopVisibility, {passive: true});
document.addEventListener('DOMContentLoaded', updateBackToTopVisibility);

function fromNow(selector = '.from-now') {
  document.querySelectorAll(selector).forEach(el => {
    const epoch = Number(el.textContent);
    const value = Number.isFinite(epoch) ? epoch * 1000 : el.getAttribute('datetime') || el.textContent;
    el.textContent = moment(value).fromNow();
  });
}

function parseJsonData(el, name, fallback) {
  const value = el.dataset[name];
  if (!value) return fallback;
  return JSON.parse(value);
}

window.cavil = {
  setupMenu() {
    const el = document.getElementById('cavil-menubar');
    if (!el) return;

    createApp(CavilMenu, {
      currentUser: el.dataset.currentUser,
      hasAdminRole: el.dataset.hasAdminRole === '1',
      initialStats: parseJsonData(el, 'stats', {missing: 0, proposals: 0}),
      roles: parseJsonData(el, 'roles', []),
      urls: parseJsonData(el, 'urls', {})
    }).mount(el);
  },

  setupProposedPatterns(currentUser, hasAdminRole) {
    const app = createApp(ProposedPatterns);
    app.config.globalProperties.currentUser = currentUser;
    app.config.globalProperties.hasAdminRole = hasAdminRole;
    app.mount('#proposed-patterns');
  },

  setupMissingLicenses(currentUser, hasAdminRole) {
    const app = createApp(MissingLicenses);
    app.config.globalProperties.currentUser = currentUser;
    app.config.globalProperties.hasAdminRole = hasAdminRole;
    app.mount('#missing-licenses');
  },

  setupClassifySnippets(hasClassifierRole) {
    const app = createApp(ClassifySnippets);
    app.config.globalProperties.hasClassifierRole = hasClassifierRole;
    app.mount('#classify-snippets');
  },

  setupEditSnippet(snippet, hasContributorRole, hasAdminRole) {
    const app = createApp(EditSnippet);
    app.config.globalProperties.currentSnippet = snippet;
    app.config.globalProperties.hasContributorRole = hasContributorRole;
    app.config.globalProperties.hasAdminRole = hasAdminRole;
    app.mount('#edit-snippet');
  },

  setupEditPattern(pattern) {
    const app = createApp(EditPattern);
    app.config.globalProperties.currentPattern = pattern;
    app.mount('#edit-pattern');
  },

  setupIgnoredMatches() {
    createApp(IgnoredMatches).mount('#ignored-matches');
  },

  setupIgnoredFiles() {
    createApp(IgnoredFiles).mount('#ignored-files');
  },

  setupApiKeys() {
    createApp(ApiKeys).mount('#api-keys');
  },

  setupKnownLicenses() {
    createApp(KnownLicenses).mount('#known-licenses');
  },

  setupKnownProducts() {
    createApp(KnownProducts).mount('#known-products');
  },

  setupLicenseDetails(licenseName) {
    const app = createApp(LicenseDetails);
    app.config.globalProperties.licenseName = licenseName;
    app.mount('#license-details');
  },

  setupRecentPatterns(hasAdminRole) {
    const app = createApp(RecentPatterns);
    app.config.globalProperties.hasAdminRole = hasAdminRole;
    app.mount('#recent-patterns');
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

  setupRecentNotes(canSeeLawyerOnly) {
    const app = createApp(RecentNotes);
    app.config.globalProperties.canSeeLawyerOnly = canSeeLawyerOnly;
    app.mount('#recent-notes');
  },

  setupReportMetadata(pkgId, hasManagerRole, hasAdminRole, hasLawyerRole, reindexUrl, shouldReindex) {
    const app = createApp(ReportMetadata);
    app.config.globalProperties.pkgId = pkgId;
    app.config.globalProperties.hasManagerRole = hasManagerRole;
    app.config.globalProperties.hasAdminRole = hasAdminRole;
    app.config.globalProperties.hasLawyerRole = hasLawyerRole;
    app.config.globalProperties.reindexUrl = reindexUrl;
    app.config.globalProperties.shouldReindex = shouldReindex;
    app.mount('#report-metadata');
  },

  setupReportDetails(pkgId, hasAdminRole, hasContributorRole, isObsolete = false) {
    const app = createApp(ReportDetails);
    app.config.globalProperties.pkgId = pkgId;
    app.config.globalProperties.hasAdminRole = hasAdminRole;
    app.config.globalProperties.hasContributorRole = hasContributorRole;
    app.config.globalProperties.isObsolete = isObsolete;
    app.mount('#report-details');
  },

  setupReviewSearch(pkg) {
    const app = createApp(ReviewSearch);
    app.config.globalProperties.currentPackage = pkg;
    app.mount('#review-search');
  },

  setupFileBrowser(pkgId, initialPath) {
    const app = createApp(FileBrowser);
    app.config.globalProperties.pkgId = pkgId;
    app.config.globalProperties.fileBrowserInitialPath = initialPath;
    app.mount('#file-browser');
  },

  setupStatistics() {
    createApp(CavilStatistics).mount('#statistics');
  },

  setupUpload(storeUrl) {
    const app = createApp(Upload);
    app.config.globalProperties.storeUrl = storeUrl;
    app.mount('#upload');
  },

  fromNow
};
