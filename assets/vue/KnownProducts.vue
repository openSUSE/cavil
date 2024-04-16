<template>
  <div>
    <div>
      <form>
        <div class="row g-4">
          <div class="col-lg-2">
            <div class="form-floating">
              <select v-model="params.limit" @change="gotoPage(1)" class="form-control">
                <option>10</option>
                <option>25</option>
                <option>50</option>
                <option>100</option>
              </select>
              <label class="form-label">Products per Page</label>
            </div>
          </div>
          <div class="col"></div>
          <div id="cavil-pkg-filter" class="col-lg-3">
            <form @submit.prevent="filterNow">
              <div class="form-floating">
                <input v-model="filter" type="text" class="form-control" placeholder="Filter" />
                <label class="form-label">Filter</label>
              </div>
            </form>
          </div>
        </div>
      </form>
      <div class="row">
        <div class="col-12">
          <table class="table table-striped table-bordered">
            <thead>
              <tr>
                <th class="link">Product</th>
                <th colspan="2">Packages</th>
              </tr>
            </thead>
            <tbody v-if="products === null">
              <tr>
                <td id="all-done" colspan="2"><i class="fas fa-sync fa-spin"></i> Loading products...</td>
              </tr>
            </tbody>
            <tbody v-else-if="products.length > 0">
              <tr v-for="product in products" :key="product.link">
                <td v-html="product.link"></td>
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
                <td id="all-done" colspan="4">No products found.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <div class="row">
        <div class="col-6 mb-4">
          <ShownEntries :end.sync="end" :start.sync="start" :total.sync="total" />
        </div>
        <div class="col-6 mb-4" id="cavil-pagination">
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
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';

export default {
  name: 'KnownProducts',
  mixins: [Refresh],
  components: {PaginationLinks, ShownEntries},
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
.table {
  margin-top: 1rem;
}
.cavil-bad-badge {
  margin-right: 10px;
}
#cavil-pkg-filter form {
  margin: 2px 0;
  white-space: nowrap;
  justify-content: flex-end;
}
#all-done {
  text-align: center;
}
</style>
