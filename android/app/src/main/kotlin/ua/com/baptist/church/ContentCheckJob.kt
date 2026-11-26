package ua.com.baptist.church

import android.app.job.JobParameters
import android.app.job.JobService

/** Щогодинна перевірка нового на сайті (див. ContentAlerts). */
class ContentCheckJob : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        Thread {
            val ok = try {
                ContentAlerts.check(applicationContext)
            } catch (e: Exception) {
                false
            }
            jobFinished(params, !ok)
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true
}
