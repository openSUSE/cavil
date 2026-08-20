<template>
  <CavilListLayout
    :current-page="currentPage"
    :end="end"
    :filter="filter"
    count-icon="fa-solid fa-box-open"
    filter-aria-label="Package review filters"
    filter-input-id="product-reviews-filter-input"
    filter-label="Filter packages"
    filter-placeholder="Filter packages"
    :page-title="currentProduct"
    plural="packages"
    singular="package"
    :start="start"
    :total="total"
    :total-pages="totalPages"
    @filter-submit="filterNow"
    @goto-page="gotoPage"
    @update:filter="filter = $event"
  >
    <template #toolbar>
      <div v-if="canCurate && isCodestream" class="cavil-curate">
        <div class="cavil-list-filter-box cavil-curate-box">
          <i class="fa-solid fa-box" aria-hidden="true"></i>
          <input
            id="cavil-product-annotation"
            v-model="annotationDraft"
            @input="annotationSaved = false"
            @keyup.enter="saveAnnotation"
            type="text"
            class="form-control"
            aria-label="Product"
            placeholder="e.g. Multi-Linux Manager"
          />
        </div>
        <button
          id="cavil-save-annotation"
          @click="saveAnnotation"
          :disabled="savingAnnotation || annotationDraft === annotationSavedValue"
          type="button"
          class="cavil-list-toggle"
        >
          <i v-if="annotationSaved" class="fa-solid fa-check" aria-hidden="true"></i>
          Save
        </button>
      </div>
    </template>

    <template #page-header>
      <details v-if="canCurate && members.length > 0" class="cavil-codestreams">
        <summary>{{ members.length }} {{ members.length === 1 ? 'codestream' : 'codestreams' }}</summary>
        <ul>
          <li v-for="name in members" :key="name">
            <a :href="codestreamUrl(name)">{{ name }}</a>
          </li>
        </ul>
      </details>
    </template>

    <template #controls>
      <button
        id="cavil-pkg-annotated"
        @click="toggleFilter('annotated')"
        :aria-pressed="params.annotated.toString()"
        :class="{'is-active': params.annotated}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.annotated" class="fa-solid fa-check" aria-hidden="true"></i>
        Annotated
      </button>
      <button
        id="cavil-pkg-attention"
        @click="toggleFilter('attention')"
        :aria-pressed="params.attention.toString()"
        :class="{'is-active': params.attention}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.attention" class="fa-solid fa-check" aria-hidden="true"></i>
        Needs attention
      </button>
      <button
        id="cavil-pkg-unresolved-matches"
        @click="toggleFilter('unresolvedMatches')"
        :aria-pressed="params.unresolvedMatches.toString()"
        :class="{'is-active': params.unresolvedMatches}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.unresolvedMatches" class="fa-solid fa-check" aria-hidden="true"></i>
        Unresolved matches
      </button>
      <button
        id="cavil-pkg-patent"
        @click="toggleFilter('patent')"
        :aria-pressed="params.patent.toString()"
        :class="{'is-active': params.patent}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.patent" class="fa-solid fa-check" aria-hidden="true"></i>
        Patent
      </button>
      <button
        id="cavil-pkg-trademark"
        @click="toggleFilter('trademark')"
        :aria-pressed="params.trademark.toString()"
        :class="{'is-active': params.trademark}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.trademark" class="fa-solid fa-check" aria-hidden="true"></i>
        Trademark
      </button>
      <button
        id="cavil-pkg-cla"
        @click="toggleFilter('cla')"
        :aria-pressed="params.cla.toString()"
        :class="{'is-active': params.cla}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.cla" class="fa-solid fa-check" aria-hidden="true"></i>
        CLA
      </button>
      <button
        id="cavil-pkg-eula"
        @click="toggleFilter('eula')"
        :aria-pressed="params.eula.toString()"
        :class="{'is-active': params.eula}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.eula" class="fa-solid fa-check" aria-hidden="true"></i>
        EULA
      </button>
      <button
        id="cavil-pkg-export-restricted"
        @click="toggleFilter('exportRestricted')"
        :aria-pressed="params.exportRestricted.toString()"
        :class="{'is-active': params.exportRestricted}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.exportRestricted" class="fa-solid fa-check" aria-hidden="true"></i>
        Export restricted
      </button>
    </template>

    <template #per-page>
      <label class="cavil-list-control">
        <span>Per page</span>
        <select v-model="params.limit" @change="gotoPage(1)" class="form-select">
          <option>10</option>
          <option>25</option>
          <option>50</option>
          <option>100</option>
        </select>
      </label>
    </template>

    <table class="cavil-list-table table">
      <thead>
        <tr>
          <th class="package">Package</th>
          <th class="state">State</th>
          <th class="report">Report</th>
        </tr>
      </thead>
      <tbody v-if="reviews === null">
        <tr>
          <td id="all-done" colspan="3" class="cavil-list-state">
            <LegalLoading message="Loading review docket..." size="small" />
          </td>
        </tr>
      </tbody>
      <tbody v-else-if="reviews.length > 0">
        <tr v-for="review in reviews" :key="review.id">
          <td class="cavil-list-package" v-html="review.package"></td>
          <td v-html="review.state"></td>
          <td class="cavil-list-report" v-html="review.report"></td>
        </tr>
      </tbody>
      <tbody v-else>
        <tr>
          <td id="all-done" colspan="3" class="cavil-list-empty-cell">
            <EmptyState message="No package reviews found." />
          </td>
        </tr>
      </tbody>
    </table>
  </CavilListLayout>
</template>

<script>
import CavilListLayout from './components/CavilListLayout.vue';
import EmptyState from './components/EmptyState.vue';
import LegalLoading from './components/LegalLoading.vue';
import {packageLink, reportLink, setupPopoverDelayed} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'ProductReviews',
  mixins: [Refresh],
  components: {CavilListLayout, EmptyState, LegalLoading},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      annotated: false,
      attention: false,
      unresolvedMatches: false,
      patent: false,
      trademark: false,
      exportRestricted: false,
      cla: false,
      eula: false,
      filter: ''
    });

    return {
      end: 0,
      params,
      reviews: null,
      refreshUrl: `/pagination/products/${this.currentProduct}`,
      filter: params.filter,
      start: 0,
      total: 0,
      annotationDraft: this.annotation,
      annotationSavedValue: this.annotation,
      annotationSaved: false,
      savingAnnotation: false
    };
  },
  computed: {
    totalPages() {
      return Math.ceil(this.total / this.params.limit);
    },
    currentPage() {
      return Math.ceil(this.end / this.params.limit);
    }
  },
  methods: {
    gotoPage(num) {
      this.cancelApiRefresh();
      const limit = this.params.limit;
      this.params.offset = num * limit - limit;
      this.reviews = null;
      this.doApiRefresh();
    },
    refreshData(data) {
      this.start = data.start;
      this.end = data.end;
      this.total = data.total;

      const reviews = [];
      for (const review of data.page) {
        reviews.push({
          package: packageLink(review),
          report: reportLink(review),
          state: review.state
        });
      }
      this.reviews = reviews;
      setupPopoverDelayed();
    },
    toggleFilter(name) {
      this.params[name] = !this.params[name];
      this.gotoPage(1);
    },
    filterNow() {
      this.cancelApiRefresh();
      this.reviews = null;
      this.doApiRefresh();
    },
    codestreamUrl(name) {
      return `/products/${encodeURIComponent(name)}`;
    },
    // Curator-only: roll this codestream up to a human product name (or clear it when left empty)
    async saveAnnotation() {
      this.savingAnnotation = true;
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(`/products/${encodeURIComponent(this.currentProduct)}/annotation`, {
        form: {product: this.annotationDraft},
        query: {_method: 'PUT'}
      });
      this.annotationSavedValue = this.annotationDraft;
      this.annotationSaved = true;
      this.savingAnnotation = false;
    }
  },
  watch: {
    ...genParamWatchers(
      'limit',
      'offset',
      'annotated',
      'attention',
      'unresolvedMatches',
      'patent',
      'trademark',
      'exportRestricted',
      'cla',
      'eula'
    ),
    filter: function (val) {
      this.params.filter = val;
      this.params.offset = 0;
      setParam('filter', val);
    }
  }
};
</script>

<style scoped>
.cavil-curate {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex: 1 1 20rem;
}
.cavil-curate-box {
  flex: 1 1 auto;
}
.cavil-curate-box input {
  width: 100%;
}
.cavil-curate .cavil-list-toggle:disabled {
  cursor: default;
  opacity: 0.55;
}
.cavil-codestreams {
  margin-bottom: 1rem;
  font-size: 0.8125rem;
}
.cavil-codestreams > summary {
  color: var(--cavil-fg-muted);
  cursor: pointer;
}
.cavil-codestreams ul {
  margin: 0.4rem 0 0;
  padding-left: 1.1rem;
  list-style: none;
}
.cavil-codestreams li {
  margin: 0.1rem 0;
}
.cavil-codestreams a {
  font-family: var(--bs-font-monospace, monospace);
  color: var(--cavil-fg-muted);
  text-decoration: none;
}
.cavil-codestreams a:hover {
  color: var(--cavil-accent);
  text-decoration: underline;
}
</style>
