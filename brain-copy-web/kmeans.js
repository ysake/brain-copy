class KMeans {
    constructor(k, maxIterations = 100) {
        this.k = k;
        this.maxIterations = maxIterations;
        this.centroids = [];
    }

    // Euclidean distance between two points
    distance(p1, p2) {
        return Math.sqrt(p1.reduce((sum, val, i) => sum + Math.pow(val - p2[i], 2), 0));
    }

    // Initialize centroids randomly
    initializeCentroids(data) {
        const centroids = [];
        const indices = new Set();
        
        while (indices.size < this.k) {
            const randomIndex = Math.floor(Math.random() * data.length);
            indices.add(randomIndex);
        }
        
        indices.forEach(index => {
            centroids.push(data[index].slice());
        });
        
        return centroids;
    }

    // Assign each point to nearest centroid
    assignClusters(data, centroids) {
        return data.map(point => {
            const distances = centroids.map(centroid => this.distance(point, centroid));
            const cluster = distances.indexOf(Math.min(...distances));
            return { point, cluster };
        });
    }

    // Update centroids based on current clusters
    updateCentroids(data, clusters) {
        const newCentroids = Array(this.k).fill(null).map(() => Array(data[0].length).fill(0));
        const counts = Array(this.k).fill(0);

        clusters.forEach(({ point, cluster }) => {
            point.forEach((val, i) => {
                newCentroids[cluster][i] += val;
            });
            counts[cluster]++;
        });

        return newCentroids.map((centroid, i) => 
            centroid.map(val => counts[i] > 0 ? val / counts[i] : val)
        );
    }

    // Main K-means algorithm
    cluster(data) {
        this.centroids = this.initializeCentroids(data);
        let clusters = [];
        
        for (let i = 0; i < this.maxIterations; i++) {
            clusters = this.assignClusters(data, this.centroids);
            const newCentroids = this.updateCentroids(data, clusters);
            
            // Check for convergence
            let converged = true;
            for (let j = 0; j < this.k; j++) {
                if (this.distance(this.centroids[j], newCentroids[j]) > 0.001) {
                    converged = false;
                    break;
                }
            }
            
            if (converged) break;
            this.centroids = newCentroids;
        }
        
        return clusters;
    }
}