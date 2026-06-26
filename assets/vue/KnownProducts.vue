<template>
  <CavilListLayout
    :current-page="currentPage"
    :end="end"
    :filter="filter"
    count-icon="fa-solid fa-box"
    filter-aria-label="Product filters"
    filter-input-id="products-filter-input"
    filter-label="Filter products"
    filter-placeholder="Filter products"
    plural="products"
    singular="product"
    :start="start"
    :total="total"
    :total-pages="totalPages"
    @filter-submit="filterNow"
    @goto-page="gotoPage"
    @update:filter="filter = $event"
  >
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
          <th class="link">Product</th>
          <th class="created">Updated</th>
          <th colspan="2">Packages</th>
        </tr>
      </thead>
      <tbody v-if="products === null">
        <tr>
          <td id="all-done" colspan="4" class="cavil-list-state">
            <i class="fa-solid fa-rotate fa-spin"></i> Loading products...
          </td>
        </tr>
      </tbody>
      <tbody v-else-if="products.length > 0">
        <tr v-for="product in products" :key="product.link">
          <td class="cavil-list-primary" v-html="product.link"></td>
          <td class="relative-time cavil-list-time">{{ product.updated }}</td>
          <td>
            <div v-if="product.unacceptable_packages > 0" class="cavil-bad-badge badge text-bg-danger">
              {{ product.unacceptable_packages }}
            </div>
            <div v-if="product.new_packages > 0" class="badge text-bg-secondary">
              {{ product.new_packages }}
            </div>
          </td>
          <td>
            <div class="badge text-bg-success">{{ product.reviewed_packages }}</div>
          </td>
        </tr>
      </tbody>
      <tbody v-else>
        <tr>
          <td id="all-done" colspan="4" class="cavil-list-empty-cell">
            <EmptyState message="No products found." />
          </td>
        </tr>
      </tbody>
    </table>
  </CavilListLayout>
</template>

<script>
import CavilListLayout from './components/CavilListLayout.vue';
import EmptyState from './components/EmptyState.vue';
import {productLink} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

export default {
  name: 'KnownProducts',
  mixins: [Refresh],
  components: {CavilListLayout, EmptyState},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      filter: ''
    });

    return {
      end: 0,
      products: null,
      params,
      refreshUrl: '/pagination/products/known',
      filter: params.filter,
      start: 0,
      total: 0
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
      this.products = null;
      this.doApiRefresh();
    },
    refreshData(data) {
      this.start = data.start;
      this.end = data.end;
      this.total = data.total;

      const products = [];
      for (const product of data.page) {
        products.push({
          link: productLink(product),
          updated: moment(product.updated_epoch * 1000).fromNow(),
          ...product
        });
      }
      this.products = products;
    },
    filterNow() {
      this.cancelApiRefresh();
      this.products = null;
      this.doApiRefresh();
    }
  },
  watch: {
    ...genParamWatchers('limit', 'offset'),
    filter: function (val) {
      this.params.filter = val;
      this.params.offset = 0;
      setParam('filter', val);
    }
  }
};
</script>

<style>
.cavil-bad-badge {
  margin-right: 10px;
}
</style>
