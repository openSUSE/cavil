<template>
  <div>
    <div>
      <div class="row">
        <div class="col-sm-12 col-md-8">
          <form class="form-inline">
            <div class="form-group mb-2 mr-sm-4">
              <label
                >Show&nbsp;
                <select v-model="params.limit" @change="gotoPage(1)" class="form-control">
                  <option>10</option>
                  <option>25</option>
                  <option>50</option>
                  <option>100</option>
                </select>
                &nbsp;entries</label
              >
            </div>
            <div class="form-check mb-2 mr-sm-2"></div>
          </form>
        </div>
        <div id="cavil-pkg-search" class="col-sm-12 col-md-4">
          <form @submit.prevent="searchNow" class="form-inline">
            <label class="col-form-label" for="inlineSearch">Filter:&nbsp;</label>
            <input v-model="search" type="text" class="form-control" id="inlineSearch" />
          </form>
        </div>
      </div>
      <div class="row">
        <div class="col-12">
          <table class="table table-striped table-bordered">
            <thead>
              <tr>
                <th class="link">Product</th>
              </tr>
            </thead>
            <tbody v-if="products === null">
              <tr>
                <td id="all-done" colspan="4"><i class="fas fa-sync fa-spin"></i> Loading products...</td>
              </tr>
            </tbody>
            <tbody v-else-if="products.length > 0">
              <tr v-for="product in products" :key="product.link">
                <td v-html="product.link"></td>
              </tr>
            </tbody>
            <tbody v-else>
              <tr>
                <td id="all-done" colspan="4">No products found.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <div class="row">
        <div class="col-6">
          <ShownEntries :end.sync="end" :start.sync="start" :total.sync="total" />
        </div>
        <div class="col-6" id="cavil-pagination">
          <PaginationLinks
            @goto-page="gotoPage"
            :end.sync="end"
            :start.sync="start"
            :total.sync="total"
            :current-page.sync="currentPage"
            :total-pages.sync="totalPages"
          />
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import PaginationLinks from './components/PaginationLinks.vue';
import ShownEntries from './components/ShownEntries.vue';
import {productLink} from './helpers/links.js';
import Refresh from './mixins/refresh.js';

export default {
  name: 'KnownProducts',
  mixins: [Refresh],
  components: {PaginationLinks, ShownEntries},
  data() {
    return {
      end: 0,
      products: null,
      params: {limit: 10, offset: 0, search: ''},
      refreshUrl: '/pagination/products/known',
      search: '',
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
          link: productLink(product)
        });
      }
      this.products = products;
    },
    searchNow() {
      this.cancelApiRefresh();
      this.products = null;
      this.doApiRefresh();
    }
  },
  watch: {
    search: function (val) {
      this.params.search = val;
      this.params.offset = 0;
    }
  }
};
</script>

<style>
.table {
  margin-top: 1rem;
}
#cavil-pkg-search form {
  margin: 2px 0;
  white-space: nowrap;
  justify-content: flex-end;
}
#all-done {
  text-align: center;
}
</style>
